#!/usr/bin/env python3
# Instrument criu's parasite page-dump (criu/pie/parasite.c) to pinpoint
# the EFAULT/partial vmsplice on the cachyos-lto kernel:
#   - drop SPLICE_F_GIFT (GIFT needs exclusively-owned anon pages),
#   - force the pipe large enough for all pages (so pipe-fill can't mask
#     the real fault),
#   - splice ONE iov at a time and, on the first failing iov, log its
#     base/len/ret so we can correlate the address to the VMA list.
import sys

path = sys.argv[1]
src = open(path).read()

OLD = (
    "\tiovs = pargs_iovs(args);\n"
    "\toff = 0;\n"
    "\tnr_segs = args->nr_segs;\n"
    "\tif (nr_segs > UIO_MAXIOV)\n"
    "\t\tnr_segs = UIO_MAXIOV;\n"
    "\twhile (1) {\n"
    "\t\tret = sys_vmsplice(p, &iovs[args->off + off], nr_segs, SPLICE_F_GIFT | SPLICE_F_NONBLOCK);\n"
    "\t\tif (ret < 0) {\n"
    "\t\t\tsys_close(p);\n"
    "\t\t\tpr_err(\"Can't splice pages to pipe (%d/%d/%d)\\n\", ret, nr_segs, args->off + off);\n"
    "\t\t\treturn -1;\n"
    "\t\t}\n"
    "\t\tspliced_bytes += ret;\n"
    "\t\toff += nr_segs;\n"
    "\t\tif (off == args->nr_segs)\n"
    "\t\t\tbreak;\n"
    "\t\tif (off + nr_segs > args->nr_segs)\n"
    "\t\t\tnr_segs = args->nr_segs - off;\n"
    "\t}\n"
)

NEW = (
    "\tiovs = pargs_iovs(args);\n"
    "\t(void)nr_segs;\n"
    "\t/* force pipe large enough for all pages so pipe-fill can't mask\n"
    "\t * the real per-iov fault (1031 = F_SETPIPE_SZ) */\n"
    "\tsys_fcntl(p, 1031, (long)args->nr_pages * PAGE_SIZE);\n"
    "\tfor (off = 0; off < args->nr_segs; off++) {\n"
    "\t\tstruct iovec *_v = &iovs[args->off + off];\n"
    "\t\tret = sys_vmsplice(p, _v, 1, SPLICE_F_NONBLOCK);\n"
    "\t\tif (ret != (int)_v->iov_len) {\n"
    "\t\t\tpr_err(\"SPLICE-DBG fail iov #%d base=%lx len=%lx ret=%d\\n\",\n"
    "\t\t\t       off, (unsigned long)_v->iov_base, (unsigned long)_v->iov_len, ret);\n"
    "\t\t\tsys_close(p);\n"
    "\t\t\treturn -1;\n"
    "\t\t}\n"
    "\t\tspliced_bytes += ret;\n"
    "\t}\n"
)

if OLD not in src:
    sys.exit("instrument-parasite: dump_pages splice loop not found (source changed?)")
open(path, "w").write(src.replace(OLD, NEW, 1))
print("instrument-parasite: patched dump_pages splice loop")
