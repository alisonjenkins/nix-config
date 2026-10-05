/* Headless VRS (attachment-based fragment shading rate) probe. See build line in run.sh. */
#define _GNU_SOURCE
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define W 64
#define H 64
#define TEXEL 8
#define RW (W / TEXEL)
#define RH (H / TEXEL)
#define COLOR_FMT VK_FORMAT_R8G8_UINT
#define RATE_FMT VK_FORMAT_R8_UINT

#define SETUP(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
    fprintf(stderr, "SETUP ERROR %s:%d %s -> %d\n", __FILE__, __LINE__, #x, (int)r_); exit(2); } } while (0)
#define SETUP_CHECK(c, msg) do { if (!(c)) { fprintf(stderr, "SETUP ERROR: %s\n", msg); exit(2); } } while (0)

static struct {
    VkInstance inst;
    VkPhysicalDevice phys;
    VkDevice dev;
    VkQueue q;
    uint32_t qfam;
    VkPhysicalDeviceMemoryProperties mem;
    VkShaderModule vs, fs;
    VkCommandPool pool;
    int supported[16];            /* rate code -> supported by device */
    int nontrivial_combiners;
    int validation;
    PFN_vkCmdSetFragmentShadingRateKHR set_rate;
} G;

/* validation capture */
static int g_vcount;
static char g_vfirst[400];
static VKAPI_ATTR VkBool32 VKAPI_CALL dbg_cb(VkDebugUtilsMessageSeverityFlagBitsEXT sev,
    VkDebugUtilsMessageTypeFlagsEXT type, const VkDebugUtilsMessengerCallbackDataEXT *d, void *u)
{
    (void)type; (void)u;
    if (sev & (VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)) {
        if (g_vcount++ == 0) snprintf(g_vfirst, sizeof g_vfirst, "%.390s", d->pMessage);
    }
    return VK_FALSE;
}

static const char *rate_name(unsigned c)
{
    static char buf[8][8];
    static int i;
    char *b = buf[i++ & 7];
    snprintf(b, 8, "%ux%u", 1u << ((c >> 2) & 3), 1u << (c & 3));
    return b;
}

static uint32_t find_mem(uint32_t bits, VkMemoryPropertyFlags want)
{
    for (uint32_t i = 0; i < G.mem.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (G.mem.memoryTypes[i].propertyFlags & want) == want) return i;
    fprintf(stderr, "SETUP ERROR: no memory type\n");
    exit(2);
}

static uint8_t *read_file(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb");
    SETUP_CHECK(f, p);
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    SETUP_CHECK(sz > 0, "empty shader file");
    uint8_t *b = malloc((size_t)sz);
    SETUP_CHECK(b && fread(b, 1, (size_t)sz, f) == (size_t)sz, "short read");
    fclose(f);
    *n = (size_t)sz;
    return b;
}

static VkShaderModule load_shader(const char *p)
{
    size_t n; uint8_t *code = read_file(p, &n);
    VkShaderModuleCreateInfo ci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = n, .pCode = (uint32_t *)code };
    VkShaderModule m; SETUP(vkCreateShaderModule(G.dev, &ci, NULL, &m));
    free(code);
    return m;
}

/* ---------- per-case config / result ---------- */
typedef struct {
    const char *name;
    VkSampleCountFlagBits samples;
    int depth;
    uint32_t views;              /* 1 = no multiview, 2 = viewMask 0b11 */
    VkFragmentShadingRateCombinerOpKHR ops[2];
    int dynamic;                 /* pipeline declares dynamic FSR state */
    int pipeline_flag;           /* RENDERING_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR */
    int use_attachment;          /* chain the FSR attachment into vkCmdBeginRendering */
    unsigned codes[8]; int ncodes;
} Cfg;

typedef struct {
    int skip; const char *skip_why;
    VkResult err; const char *stage;
    uint32_t layers;
    uint8_t req[RW * RH];
    uint8_t rate[2][W * H];
    uint8_t pos[2][W * H];
    int vcount; char vfirst[400];
} Out;

typedef struct {
    int tiles[16], exact[16];
    unsigned obs[16];            /* mask of observed codes per requested code */
    double distinct[16];
    int layers_equal;
} Rep;

static Cfg base_cfg(const char *name)
{
    Cfg c = { .name = name, .samples = VK_SAMPLE_COUNT_1_BIT, .views = 1,
              .ops = { VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR, VK_FRAGMENT_SHADING_RATE_COMBINER_OP_REPLACE_KHR },
              .dynamic = 1, .use_attachment = 1 };
    const unsigned all[] = { 0, 5, 10, 4, 1 };   /* 1x1 2x2 4x4 2x1 1x2 */
    for (unsigned i = 0; i < 5; i++) if (G.supported[all[i]]) c.codes[c.ncodes++] = all[i];
    return c;
}

/* ---------- resources ---------- */
typedef struct { VkImage img; VkDeviceMemory mem; VkImageView view; } Img;
typedef struct { VkBuffer buf; VkDeviceMemory mem; void *map; } Buf;

typedef struct {
    Img color, resolve, depth, rate;
    Buf stage, readback;
    VkPipelineLayout pl;
    VkPipeline pipe;
    VkCommandBuffer cb;
    VkFence fence;
} Res;

static VkResult mk_img(Img *o, VkFormat f, uint32_t w, uint32_t h, uint32_t layers, VkSampleCountFlagBits s,
                       VkImageUsageFlags u, VkImageAspectFlags asp)
{
    VkImageCreateInfo ci = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = f,
        .extent = { w, h, 1 }, .mipLevels = 1, .arrayLayers = layers, .samples = s, .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = u, .sharingMode = VK_SHARING_MODE_EXCLUSIVE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
    VkResult r = vkCreateImage(G.dev, &ci, NULL, &o->img);
    if (r) return r;
    VkMemoryRequirements mr; vkGetImageMemoryRequirements(G.dev, o->img, &mr);
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size,
        .memoryTypeIndex = find_mem(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) };
    if ((r = vkAllocateMemory(G.dev, &ai, NULL, &o->mem))) return r;
    if ((r = vkBindImageMemory(G.dev, o->img, o->mem, 0))) return r;
    VkImageViewCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = o->img,
        .viewType = layers > 1 ? VK_IMAGE_VIEW_TYPE_2D_ARRAY : VK_IMAGE_VIEW_TYPE_2D, .format = f,
        .subresourceRange = { asp, 0, 1, 0, layers } };
    return vkCreateImageView(G.dev, &vi, NULL, &o->view);
}

static VkResult mk_buf(Buf *o, VkDeviceSize sz, VkBufferUsageFlags u)
{
    VkBufferCreateInfo ci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = sz, .usage = u, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    VkResult r = vkCreateBuffer(G.dev, &ci, NULL, &o->buf);
    if (r) return r;
    VkMemoryRequirements mr; vkGetBufferMemoryRequirements(G.dev, o->buf, &mr);
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size,
        .memoryTypeIndex = find_mem(mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) };
    if ((r = vkAllocateMemory(G.dev, &ai, NULL, &o->mem))) return r;
    if ((r = vkBindBufferMemory(G.dev, o->buf, o->mem, 0))) return r;
    return vkMapMemory(G.dev, o->mem, 0, VK_WHOLE_SIZE, 0, &o->map);
}

static void del_img(Img *i)
{
    if (i->view) vkDestroyImageView(G.dev, i->view, NULL);
    if (i->img) vkDestroyImage(G.dev, i->img, NULL);
    if (i->mem) vkFreeMemory(G.dev, i->mem, NULL);
}
static void del_buf(Buf *b)
{
    if (b->buf) vkDestroyBuffer(G.dev, b->buf, NULL);
    if (b->mem) vkFreeMemory(G.dev, b->mem, NULL);
}

static void bar(VkCommandBuffer cb, VkImage img, VkImageAspectFlags asp, uint32_t layers, VkImageLayout o, VkImageLayout n)
{
    VkImageMemoryBarrier2 b = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, .srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, .dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
        .oldLayout = o, .newLayout = n, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = img, .subresourceRange = { asp, 0, 1, 0, layers } };
    VkDependencyInfo d = { .sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO, .imageMemoryBarrierCount = 1, .pImageMemoryBarriers = &b };
    vkCmdPipelineBarrier2(cb, &d);
}

static int fmt_samples_ok(VkFormat f, VkSampleCountFlagBits s, VkImageUsageFlags u)
{
    VkImageFormatProperties p;
    VkResult r = vkGetPhysicalDeviceImageFormatProperties(G.phys, f, VK_IMAGE_TYPE_2D, VK_IMAGE_TILING_OPTIMAL, u, 0, &p);
    return r == VK_SUCCESS && (p.sampleCounts & s);
}

#define CASE_TRY(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { o->err = r_; o->stage = #x; goto done; } } while (0)

static void run_case(const Cfg *c, Out *o)
{
    Res R; memset(&R, 0, sizeof R);
    memset(o, 0, sizeof *o);
    int before = g_vcount;
    o->layers = c->views;
    const int msaa = c->samples != VK_SAMPLE_COUNT_1_BIT;
    VkImageUsageFlags cu = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (!fmt_samples_ok(COLOR_FMT, c->samples, cu)) { o->skip = 1; o->skip_why = "color format/sample count unsupported"; return; }
    if (c->depth && !fmt_samples_ok(VK_FORMAT_D32_SFLOAT, c->samples, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT)) {
        o->skip = 1; o->skip_why = "D32 sample count unsupported"; return; }

    for (int ty = 0; ty < RH; ty++) for (int tx = 0; tx < RW; tx++)
        o->req[ty * RW + tx] = (uint8_t)c->codes[(tx + ty) % c->ncodes];

    CASE_TRY(mk_img(&R.color, COLOR_FMT, W, H, c->views, c->samples, cu, VK_IMAGE_ASPECT_COLOR_BIT));
    if (msaa) CASE_TRY(mk_img(&R.resolve, COLOR_FMT, W, H, c->views, VK_SAMPLE_COUNT_1_BIT, cu, VK_IMAGE_ASPECT_COLOR_BIT));
    if (c->depth) CASE_TRY(mk_img(&R.depth, VK_FORMAT_D32_SFLOAT, W, H, c->views, c->samples,
                                  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_ASPECT_DEPTH_BIT));
    CASE_TRY(mk_img(&R.rate, RATE_FMT, RW, RH, 1, VK_SAMPLE_COUNT_1_BIT,
                    VK_IMAGE_USAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR | VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_IMAGE_ASPECT_COLOR_BIT));
    CASE_TRY(mk_buf(&R.stage, 4096, VK_BUFFER_USAGE_TRANSFER_SRC_BIT));
    CASE_TRY(mk_buf(&R.readback, (VkDeviceSize)W * H * 2 * 2, VK_BUFFER_USAGE_TRANSFER_DST_BIT));
    memcpy(R.stage.map, o->req, sizeof o->req);
    memset(R.readback.map, 0xEE, (size_t)W * H * 2 * 2);

    /* pipeline */
    VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    CASE_TRY(vkCreatePipelineLayout(G.dev, &plci, NULL, &R.pl));
    VkPipelineShaderStageCreateInfo st[2] = {
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = G.vs, .pName = "main" },
        { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = G.fs, .pName = "main" } };
    VkPipelineVertexInputStateCreateInfo vi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
    VkPipelineInputAssemblyStateCreateInfo ia = { .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
    VkPipelineViewportStateCreateInfo vp = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
    VkPipelineRasterizationStateCreateInfo rs = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE, .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f };
    VkPipelineMultisampleStateCreateInfo ms = { .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = c->samples };
    VkPipelineDepthStencilStateCreateInfo ds = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = c->depth, .depthWriteEnable = c->depth, .depthCompareOp = VK_COMPARE_OP_LESS };
    VkPipelineColorBlendAttachmentState cba = { .colorWriteMask = 0xF };
    VkPipelineColorBlendStateCreateInfo cb = { .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &cba };
    VkDynamicState dyn[3] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_FRAGMENT_SHADING_RATE_KHR };
    VkPipelineDynamicStateCreateInfo dsi = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = c->dynamic ? 3 : 2, .pDynamicStates = dyn };
    VkFormat cfmt = COLOR_FMT;
    VkPipelineFragmentShadingRateStateCreateInfoKHR sfs = { .sType = VK_STRUCTURE_TYPE_PIPELINE_FRAGMENT_SHADING_RATE_STATE_CREATE_INFO_KHR,
        .fragmentSize = { 1, 1 }, .combinerOps = { c->ops[0], c->ops[1] } };
    VkPipelineRenderingCreateInfo ri = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .pNext = c->dynamic ? NULL : &sfs, .viewMask = c->views > 1 ? 3u : 0u, .colorAttachmentCount = 1, .pColorAttachmentFormats = &cfmt,
        .depthAttachmentFormat = c->depth ? VK_FORMAT_D32_SFLOAT : VK_FORMAT_UNDEFINED };
    VkGraphicsPipelineCreateInfo gp = { .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .pNext = &ri,
        .flags = c->pipeline_flag ? VK_PIPELINE_CREATE_RENDERING_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR : 0,
        .stageCount = 2, .pStages = st, .pVertexInputState = &vi, .pInputAssemblyState = &ia, .pViewportState = &vp,
        .pRasterizationState = &rs, .pMultisampleState = &ms, .pDepthStencilState = &ds, .pColorBlendState = &cb,
        .pDynamicState = &dsi, .layout = R.pl };
    CASE_TRY(vkCreateGraphicsPipelines(G.dev, VK_NULL_HANDLE, 1, &gp, NULL, &R.pipe));

    VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = G.pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    CASE_TRY(vkAllocateCommandBuffers(G.dev, &cai, &R.cb));
    VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    CASE_TRY(vkBeginCommandBuffer(R.cb, &bi));

    const VkImageAspectFlags CA = VK_IMAGE_ASPECT_COLOR_BIT;
    bar(R.cb, R.color.img, CA, c->views, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    if (msaa) bar(R.cb, R.resolve.img, CA, c->views, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    if (c->depth) bar(R.cb, R.depth.img, VK_IMAGE_ASPECT_DEPTH_BIT, c->views, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL);
    bar(R.cb, R.rate.img, CA, 1, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkBufferImageCopy up = { .imageSubresource = { CA, 0, 0, 1 }, .imageExtent = { RW, RH, 1 } };
    vkCmdCopyBufferToImage(R.cb, R.stage.buf, R.rate.img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &up);
    bar(R.cb, R.rate.img, CA, 1, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_FRAGMENT_SHADING_RATE_ATTACHMENT_OPTIMAL_KHR);

    VkRenderingAttachmentInfo catt = { .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, .imageView = R.color.view,
        .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = msaa ? VK_ATTACHMENT_STORE_OP_DONT_CARE : VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue.color.uint32 = { 255, 255, 0, 0 } };
    if (msaa) { catt.resolveMode = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT; catt.resolveImageView = R.resolve.view;
                catt.resolveImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL; }
    VkRenderingAttachmentInfo datt = { .sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, .imageView = R.depth.view,
        .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE, .clearValue.depthStencil = { 1.0f, 0 } };
    VkRenderingFragmentShadingRateAttachmentInfoKHR fsr = { .sType = VK_STRUCTURE_TYPE_RENDERING_FRAGMENT_SHADING_RATE_ATTACHMENT_INFO_KHR,
        .imageView = R.rate.view, .imageLayout = VK_IMAGE_LAYOUT_FRAGMENT_SHADING_RATE_ATTACHMENT_OPTIMAL_KHR,
        .shadingRateAttachmentTexelSize = { TEXEL, TEXEL } };
    VkRenderingInfo rinfo = { .sType = VK_STRUCTURE_TYPE_RENDERING_INFO, .pNext = c->use_attachment ? &fsr : NULL,
        .renderArea = { { 0, 0 }, { W, H } }, .layerCount = 1, .viewMask = c->views > 1 ? 3u : 0u,
        .colorAttachmentCount = 1, .pColorAttachments = &catt, .pDepthAttachment = c->depth ? &datt : NULL };
    vkCmdBeginRendering(R.cb, &rinfo);
    vkCmdBindPipeline(R.cb, VK_PIPELINE_BIND_POINT_GRAPHICS, R.pipe);
    VkViewport vpt = { 0, 0, W, H, 0, 1 }; VkRect2D sc = { { 0, 0 }, { W, H } };
    vkCmdSetViewport(R.cb, 0, 1, &vpt); vkCmdSetScissor(R.cb, 0, 1, &sc);
    if (c->dynamic) {
        VkExtent2D one = { 1, 1 };
        VkFragmentShadingRateCombinerOpKHR ops[2] = { c->ops[0], c->ops[1] };
        G.set_rate(R.cb, &one, ops);
    }
    vkCmdDraw(R.cb, 3, 1, 0, 0);
    vkCmdEndRendering(R.cb);

    Img *src = msaa ? &R.resolve : &R.color;
    bar(R.cb, src->img, CA, c->views, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    for (uint32_t l = 0; l < c->views; l++) {
        VkBufferImageCopy cp = { .bufferOffset = (VkDeviceSize)l * W * H * 2, .imageSubresource = { CA, 0, l, 1 }, .imageExtent = { W, H, 1 } };
        vkCmdCopyImageToBuffer(R.cb, src->img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, R.readback.buf, 1, &cp);
    }
    CASE_TRY(vkEndCommandBuffer(R.cb));
    VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    CASE_TRY(vkCreateFence(G.dev, &fci, NULL, &R.fence));
    VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &R.cb };
    CASE_TRY(vkQueueSubmit(G.q, 1, &si, R.fence));
    CASE_TRY(vkWaitForFences(G.dev, 1, &R.fence, VK_TRUE, 10ull * 1000000000ull));

    const uint8_t *rb = R.readback.map;
    for (uint32_t l = 0; l < c->views; l++)
        for (int i = 0; i < W * H; i++) {
            o->rate[l][i] = rb[(size_t)l * W * H * 2 + (size_t)i * 2];
            o->pos[l][i] = rb[(size_t)l * W * H * 2 + (size_t)i * 2 + 1];
        }
done:
    if (R.fence) vkDestroyFence(G.dev, R.fence, NULL);
    if (R.cb) vkFreeCommandBuffers(G.dev, G.pool, 1, &R.cb);
    if (R.pipe) vkDestroyPipeline(G.dev, R.pipe, NULL);
    if (R.pl) vkDestroyPipelineLayout(G.dev, R.pl, NULL);
    del_buf(&R.readback); del_buf(&R.stage);
    del_img(&R.rate); del_img(&R.depth); del_img(&R.resolve); del_img(&R.color);
    o->vcount = g_vcount - before;
    if (o->vcount) snprintf(o->vfirst, sizeof o->vfirst, "%s", g_vfirst);
}

/* ---------- analysis ---------- */
static void analyze(const Out *o, Rep *r)
{
    memset(r, 0, sizeof *r);
    r->layers_equal = 1;
    if (o->layers > 1 && (memcmp(o->rate[0], o->rate[1], W * H) || memcmp(o->pos[0], o->pos[1], W * H))) r->layers_equal = 0;
    for (int ty = 0; ty < RH; ty++) for (int tx = 0; tx < RW; tx++) {
        unsigned req = o->req[ty * RW + tx];
        int exact = 1; unsigned mask = 0;
        for (uint32_t l = 0; l < o->layers; l++) {
            int seen[256] = { 0 }, nd = 0;
            for (int y = 0; y < TEXEL; y++) for (int x = 0; x < TEXEL; x++) {
                int i = (ty * TEXEL + y) * W + tx * TEXEL + x;
                unsigned v = o->rate[l][i];
                mask |= 1u << (v & 15);
                if (v != req) exact = 0;
                if (l == 0 && !seen[o->pos[l][i]]) { seen[o->pos[l][i]] = 1; nd++; }
            }
            if (l == 0) r->distinct[req] += nd;
        }
        r->tiles[req]++; r->exact[req] += exact; r->obs[req] |= mask;
    }
    for (int c = 0; c < 16; c++) if (r->tiles[c]) r->distinct[c] /= r->tiles[c];
}

static int rep_applied(const Rep *r)       /* every requested code seen exactly, incl. non-1x1 */
{
    int nonTrivial = 0;
    for (int c = 0; c < 16; c++) if (r->tiles[c]) { if (r->exact[c] != r->tiles[c]) return 0; if (c) nonTrivial = 1; }
    return nonTrivial;
}
static int rep_none_applied(const Rep *r)  /* all pixels observed 1x1 */
{
    for (int c = 0; c < 16; c++) if (r->tiles[c] && r->obs[c] != 1u) return 0;
    return 1;
}

static void rep_str(const Rep *r, char *b, size_t n)
{
    size_t k = 0; b[0] = 0;
    for (int c = 0; c < 16 && k < n; c++) if (r->tiles[c]) {
        k += (size_t)snprintf(b + k, n - k, "%s:%d/%d", rate_name(c), r->exact[c], r->tiles[c]);
        if (r->exact[c] != r->tiles[c]) {
            k += (size_t)snprintf(b + k, n - k, "obs{");
            for (int o = 0; o < 16; o++) if (r->obs[c] & (1u << o)) k += (size_t)snprintf(b + k, n - k, "%s,", rate_name(o));
            k += (size_t)snprintf(b + k, n - k, "}");
        }
        k += (size_t)snprintf(b + k, n - k, "(inv/tile=%.0f) ", r->distinct[c]);
    }
}

typedef struct { char verdict[16]; char text[1400]; } Ans;

static void catf(char *b, size_t n, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
#include <stdarg.h>
static void catf(char *b, size_t n, const char *fmt, ...)
{
    size_t l = strlen(b); va_list a; va_start(a, fmt); vsnprintf(b + l, n - l, fmt, a); va_end(a);
}

/* run + describe one case; returns 1 if applied, 0 if not, -1 if could not run */
static int do_case(const Cfg *c, Ans *a, Out *o, Rep *r)
{
    run_case(c, o);
    if (o->skip) { catf(a->text, sizeof a->text, "[%s] SKIP(%s) ", c->name, o->skip_why); return -1; }
    if (o->err) { catf(a->text, sizeof a->text, "[%s] ERR %d at %s ", c->name, (int)o->err, o->stage); return -1; }
    analyze(o, r);
    char s[600]; rep_str(r, s, sizeof s);
    catf(a->text, sizeof a->text, "[%s] %s%s ", c->name, s, o->layers > 1 ? (r->layers_equal ? "views-identical " : "VIEWS-DIFFER ") : "");
    if (o->vcount) catf(a->text, sizeof a->text, "VAL(%d): %.120s ", o->vcount, o->vfirst);
    return rep_applied(r);
}

/* ---------- questions ---------- */
static Ans q1(void)
{
    Ans a = { "", "" }; Out *o = malloc(sizeof *o); Rep r;
    Cfg c = base_cfg("1spp,nodepth,dyn");
    int ok = do_case(&c, &a, o, &r);
    snprintf(a.verdict, sizeof a.verdict, ok < 0 ? "INCONCLUSIVE" : ok ? "PASS" : "FAIL");
    if (!G.supported[10]) {
        Cfg d = base_cfg("EXTRA:request-unsupported-4x4"); d.ncodes = 3; d.codes[0] = 0; d.codes[1] = 10; d.codes[2] = 14;
        catf(a.text, sizeof a.text, "| 4x4 not in device rate list (maxFragmentSize 2x2); requesting anyway: ");
        do_case(&d, &a, o, &r);
    }
    free(o); return a;
}

static Ans q2(void)
{
    Ans a = { "", "" }; Out *o = malloc(sizeof *o); Rep r; int res[2];
    Cfg c = base_cfg("nodepth"); res[0] = do_case(&c, &a, o, &r);
    c = base_cfg("D32"); c.depth = 1; res[1] = do_case(&c, &a, o, &r);
    snprintf(a.verdict, sizeof a.verdict, (res[0] < 0 || res[1] < 0) ? "INCONCLUSIVE" : (res[0] && res[1]) ? "PASS" : "FAIL");
    free(o); return a;
}

static Ans q3(void)
{
    Ans a = { "", "" }; Out *o = malloc(sizeof *o); Rep r;
    const VkSampleCountFlagBits sc[4] = { VK_SAMPLE_COUNT_1_BIT, VK_SAMPLE_COUNT_2_BIT, VK_SAMPLE_COUNT_4_BIT, VK_SAMPLE_COUNT_8_BIT };
    int res[4]; char nm[4][8];
    for (int i = 0; i < 4; i++) {
        snprintf(nm[i], 8, "%dx", (int)sc[i]);
        Cfg c = base_cfg(nm[i]); c.samples = sc[i];
        c.ncodes = 0; const unsigned three[] = { 0, 5, 10 };
        for (int k = 0; k < 3; k++) if (G.supported[three[k]]) c.codes[c.ncodes++] = three[k];
        res[i] = do_case(&c, &a, o, &r);
        if (res[i] == 0 && rep_none_applied(&r)) catf(a.text, sizeof a.text, "(=> fell back to 1x1) ");
    }
    snprintf(a.verdict, sizeof a.verdict, (res[0] < 0 || res[1] < 0 || res[2] < 0) ? "INCONCLUSIVE" : (res[0] == 1 && res[1] == 1 && res[2] == 1) ? "PASS" : "FAIL");
    free(o); return a;
}

static Ans q4(void)
{
    Ans a = { "", "" }; Out *o = malloc(sizeof *o); Rep r;
    Cfg c = base_cfg("multiview2,1-layer-rate"); c.views = 2;
    int ok = do_case(&c, &a, o, &r);
    snprintf(a.verdict, sizeof a.verdict, ok < 0 ? "INCONCLUSIVE" : (ok && r.layers_equal) ? "PASS" : "FAIL");
    free(o); return a;
}

static Ans q5(void)
{
    Ans a = { "", "" }; Out *o = malloc(sizeof *o); Rep r; int res[8], n = 0;
    struct { const char *nm; VkFragmentShadingRateCombinerOpKHR op1; int flag; int attach; } t[] = {
        { "{KEEP,REPLACE}", VK_FRAGMENT_SHADING_RATE_COMBINER_OP_REPLACE_KHR, 0, 1 },
        { "{KEEP,KEEP}", VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR, 0, 1 },
        { "{KEEP,REPLACE}+pipeFlag", VK_FRAGMENT_SHADING_RATE_COMBINER_OP_REPLACE_KHR, 1, 1 },
        { "{KEEP,REPLACE},noAttachment", VK_FRAGMENT_SHADING_RATE_COMBINER_OP_REPLACE_KHR, 0, 0 },
        { "{KEEP,MAX}", VK_FRAGMENT_SHADING_RATE_COMBINER_OP_MAX_KHR, 0, 1 },
        { "{KEEP,MIN}", VK_FRAGMENT_SHADING_RATE_COMBINER_OP_MIN_KHR, 0, 1 },
    };
    for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
        if (t[i].op1 >= VK_FRAGMENT_SHADING_RATE_COMBINER_OP_MIN_KHR && t[i].op1 <= VK_FRAGMENT_SHADING_RATE_COMBINER_OP_MUL_KHR
            && t[i].op1 != VK_FRAGMENT_SHADING_RATE_COMBINER_OP_REPLACE_KHR && !G.nontrivial_combiners) {
            catf(a.text, sizeof a.text, "[%s] not supported (nonTrivialCombinerOps=false) ", t[i].nm); continue; }
        Cfg c = base_cfg(t[i].nm); c.ops[1] = t[i].op1; c.pipeline_flag = t[i].flag; c.use_attachment = t[i].attach;
        res[n++] = do_case(&c, &a, o, &r);
        if (res[n - 1] == 0 && rep_none_applied(&r)) catf(a.text, sizeof a.text, "(=> NOT applied) ");
    }
    /* res[0]=REPLACE ok, res[1]=KEEP must NOT apply (checked via text), res[2]=flag */
    snprintf(a.verdict, sizeof a.verdict, (res[0] < 0) ? "INCONCLUSIVE" : (res[0] == 1 && res[1] == 0 && res[2] == 1) ? "PASS" : "FAIL");
    free(o); return a;
}

static Ans q6(void)
{
    Ans a = { "", "" }; Out *o = malloc(sizeof *o); Rep r; int res[2];
    Cfg c = base_cfg("static{KEEP,REPLACE}"); c.dynamic = 0; res[0] = do_case(&c, &a, o, &r);
    c = base_cfg("static{KEEP,KEEP}(control)"); c.dynamic = 0; c.ops[1] = VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR;
    res[1] = do_case(&c, &a, o, &r);
    if (res[1] == 0 && rep_none_applied(&r)) catf(a.text, sizeof a.text, "(control not applied, as expected) ");
    snprintf(a.verdict, sizeof a.verdict, res[0] < 0 ? "INCONCLUSIVE" : res[0] ? "PASS" : "FAIL");
    free(o); return a;
}

/* ---------- setup ---------- */
static void setup(void)
{
    uint32_t n = 0;
    SETUP(vkEnumerateInstanceLayerProperties(&n, NULL));
    VkLayerProperties *lp = calloc(n ? n : 1, sizeof *lp);
    SETUP(vkEnumerateInstanceLayerProperties(&n, lp));
    for (uint32_t i = 0; i < n; i++) if (!strcmp(lp[i].layerName, "VK_LAYER_KHRONOS_validation")) G.validation = 1;
    free(lp);
    if (getenv("VRS_NOVALIDATE")) G.validation = 0;
    const char *layers[] = { "VK_LAYER_KHRONOS_validation" };
    const char *iexts[] = { VK_EXT_DEBUG_UTILS_EXTENSION_NAME };
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .pApplicationName = "vrs_probe", .apiVersion = VK_API_VERSION_1_3 };
    VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
        .enabledLayerCount = G.validation, .ppEnabledLayerNames = layers,
        .enabledExtensionCount = G.validation, .ppEnabledExtensionNames = iexts };
    SETUP(vkCreateInstance(&ici, NULL, &G.inst));
    if (G.validation) {
        PFN_vkCreateDebugUtilsMessengerEXT cm = (PFN_vkCreateDebugUtilsMessengerEXT)vkGetInstanceProcAddr(G.inst, "vkCreateDebugUtilsMessengerEXT");
        VkDebugUtilsMessengerCreateInfoEXT mi = { .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
            .messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, .pfnUserCallback = dbg_cb };
        VkDebugUtilsMessengerEXT m; SETUP_CHECK(cm, "no debug utils"); SETUP(cm(G.inst, &mi, NULL, &m));
    }

    uint32_t np = 0; SETUP(vkEnumeratePhysicalDevices(G.inst, &np, NULL));
    VkPhysicalDevice *pd = calloc(np ? np : 1, sizeof *pd);
    SETUP(vkEnumeratePhysicalDevices(G.inst, &np, pd));
    for (uint32_t i = 0; i < np; i++) {
        VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd[i], &p);
        printf("device %u: %s\n", i, p.deviceName);
        if (!G.phys && strstr(p.deviceName, "9070")) G.phys = pd[i];
    }
    free(pd);
    SETUP_CHECK(G.phys, "no device with '9070' in name");

    VkPhysicalDeviceFragmentShadingRatePropertiesKHR fp = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_PROPERTIES_KHR };
    VkPhysicalDeviceProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &fp };
    vkGetPhysicalDeviceProperties2(G.phys, &p2);
    printf("selected: %s  api %u.%u.%u\n", p2.properties.deviceName, VK_VERSION_MAJOR(p2.properties.apiVersion),
           VK_VERSION_MINOR(p2.properties.apiVersion), VK_VERSION_PATCH(p2.properties.apiVersion));
    printf("props: texel min %ux%u max %ux%u maxAspect %u layered=%d maxRastSamples=%d nonTrivialCombiners=%d maxFragSize %ux%u "
           "primRateMultiVP=%d noFragShaderInvocations(coarse)=%d\n",
           fp.minFragmentShadingRateAttachmentTexelSize.width, fp.minFragmentShadingRateAttachmentTexelSize.height,
           fp.maxFragmentShadingRateAttachmentTexelSize.width, fp.maxFragmentShadingRateAttachmentTexelSize.height,
           fp.maxFragmentShadingRateAttachmentTexelSizeAspectRatio, fp.layeredShadingRateAttachments,
           (int)fp.maxFragmentShadingRateRasterizationSamples, fp.fragmentShadingRateNonTrivialCombinerOps,
           fp.maxFragmentSize.width, fp.maxFragmentSize.height, fp.primitiveFragmentShadingRateWithMultipleViewports,
           fp.fragmentShadingRateWithFragmentShaderInterlock);
    SETUP_CHECK(fp.minFragmentShadingRateAttachmentTexelSize.width <= TEXEL && fp.maxFragmentShadingRateAttachmentTexelSize.width >= TEXEL,
                "8x8 texel size not supported");
    G.nontrivial_combiners = fp.fragmentShadingRateNonTrivialCombinerOps;

    PFN_vkGetPhysicalDeviceFragmentShadingRatesKHR gr =
        (PFN_vkGetPhysicalDeviceFragmentShadingRatesKHR)vkGetInstanceProcAddr(G.inst, "vkGetPhysicalDeviceFragmentShadingRatesKHR");
    SETUP_CHECK(gr, "no vkGetPhysicalDeviceFragmentShadingRatesKHR");
    uint32_t nr = 0; SETUP(gr(G.phys, &nr, NULL));
    VkPhysicalDeviceFragmentShadingRateKHR *rates = calloc(nr, sizeof *rates);
    for (uint32_t i = 0; i < nr; i++) rates[i].sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_KHR;
    SETUP(gr(G.phys, &nr, rates));
    printf("supported rates (size:sampleCountsMask):");
    for (uint32_t i = 0; i < nr; i++) {
        printf(" %ux%u:0x%x", rates[i].fragmentSize.width, rates[i].fragmentSize.height, rates[i].sampleCounts);
        unsigned lw = 0, lh = 0;
        while ((1u << lw) < rates[i].fragmentSize.width) lw++;
        while ((1u << lh) < rates[i].fragmentSize.height) lh++;
        G.supported[(lw << 2) | lh] = 1;
    }
    printf("\n");
    free(rates);

    VkFormatProperties2 fpr = { .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2 };
    vkGetPhysicalDeviceFormatProperties2(G.phys, RATE_FMT, &fpr);
    int fmt_ok = !!(fpr.formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR);
    printf("R8_UINT optimal features has FRAGMENT_SHADING_RATE_ATTACHMENT: %s\n", fmt_ok ? "yes" : "NO");
    SETUP_CHECK(fmt_ok, "R8_UINT lacks FSR attachment feature");
    vkGetPhysicalDeviceMemoryProperties(G.phys, &G.mem);

    uint32_t nq = 0; vkGetPhysicalDeviceQueueFamilyProperties(G.phys, &nq, NULL);
    VkQueueFamilyProperties *qp = calloc(nq, sizeof *qp); vkGetPhysicalDeviceQueueFamilyProperties(G.phys, &nq, qp);
    int found = 0;
    for (uint32_t i = 0; i < nq; i++) if (qp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { G.qfam = i; found = 1; break; }
    free(qp);
    SETUP_CHECK(found, "no graphics queue");

    VkPhysicalDeviceFragmentShadingRateFeaturesKHR ff = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR };
    VkPhysicalDeviceVulkan13Features f13 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, .pNext = &ff };
    VkPhysicalDeviceVulkan11Features f11 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES, .pNext = &f13 };
    VkPhysicalDeviceFeatures2 f2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &f11 };
    vkGetPhysicalDeviceFeatures2(G.phys, &f2);
    printf("features: pipelineRate=%d attachmentRate=%d primitiveRate=%d dynamicRendering=%d sync2=%d multiview=%d\n",
           ff.pipelineFragmentShadingRate, ff.attachmentFragmentShadingRate, ff.primitiveFragmentShadingRate,
           f13.dynamicRendering, f13.synchronization2, f11.multiview);
    SETUP_CHECK(ff.attachmentFragmentShadingRate && ff.pipelineFragmentShadingRate && f13.dynamicRendering && f13.synchronization2 && f11.multiview,
                "required features missing");
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = G.qfam, .queueCount = 1, .pQueuePriorities = &prio };
    const char *dext[] = { VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME };
    VkPhysicalDeviceFragmentShadingRateFeaturesKHR ffe = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
        .pipelineFragmentShadingRate = VK_TRUE, .attachmentFragmentShadingRate = VK_TRUE };
    VkPhysicalDeviceVulkan13Features f13e = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, .pNext = &ffe,
        .dynamicRendering = VK_TRUE, .synchronization2 = VK_TRUE };
    VkPhysicalDeviceVulkan11Features f11e = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES, .pNext = &f13e, .multiview = VK_TRUE };
    VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f11e, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci,
        .enabledExtensionCount = 1, .ppEnabledExtensionNames = dext };
    SETUP(vkCreateDevice(G.phys, &dci, NULL, &G.dev));
    vkGetDeviceQueue(G.dev, G.qfam, 0, &G.q);
    G.set_rate = (PFN_vkCmdSetFragmentShadingRateKHR)vkGetDeviceProcAddr(G.dev, "vkCmdSetFragmentShadingRateKHR");
    SETUP_CHECK(G.set_rate, "no vkCmdSetFragmentShadingRateKHR");
    VkCommandPoolCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = G.qfam };
    SETUP(vkCreateCommandPool(G.dev, &pci, NULL, &G.pool));
    G.vs = load_shader("vrs.vert.spv");
    G.fs = load_shader("vrs.frag.spv");
    printf("validation layer: %s\n", G.validation ? "ON" : "off");
}

int main(void)
{
    setup();
    struct { const char *id; const char *what; Ans (*fn)(void); } qs[] = {
        { "Q1", "attachment rates applied (dyn rendering, R8_UINT 8x8)", q1 },
        { "Q2", "no depth vs D32_SFLOAT", q2 },
        { "Q3", "MSAA 1/2/4/8 + resolve", q3 },
        { "Q4", "multiview 2 views, 1-layer rate image", q4 },
        { "Q5", "combiner ops / pipeline flag", q5 },
        { "Q6", "static (non-dynamic) pipeline rate", q6 },
    };
    Ans ans[6];
    for (int i = 0; i < 6; i++) ans[i] = qs[i].fn();
    printf("\n==== SUMMARY ====\n");
    for (int i = 0; i < 6; i++) printf("%s | %-12s | %s\n    %s\n", qs[i].id, ans[i].verdict, qs[i].what, ans[i].text);
    return 0;
}
