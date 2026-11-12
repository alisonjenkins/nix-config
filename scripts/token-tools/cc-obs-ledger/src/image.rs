//! Image dimension sniffing and token estimation from base64 tool results.

/// Anthropic's published vision sizing cap on the long edge in pixels, an estimate.
const MAX_LONG_EDGE: f64 = 1568.0;
/// Anthropic's published vision sizing cap on total pixel count, an estimate.
const MAX_PIXELS: f64 = 1_150_000.0;
/// Anthropic's published vision sizing divisor (pixels per token), an estimate.
const PIXELS_PER_TOKEN: f64 = 750.0;
/// Fallback token estimate when dimensions cannot be read: the cap at the size limit above.
pub const FALLBACK_IMAGE_TOKENS: u64 = 1600;
/// Maximum base64 prefix inspected for image headers (256 KiB).
const MAX_BASE64_PREFIX: usize = 256 * 1024;
const PNG_SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Estimates Claude vision tokens for an image of `width` by `height` pixels.
pub fn image_tokens(width: u32, height: u32) -> u64 {
    if width == 0 || height == 0 {
        return 0;
    }
    let mut w = f64::from(width);
    let mut h = f64::from(height);
    let long_edge = w.max(h);
    if long_edge > MAX_LONG_EDGE {
        let scale = MAX_LONG_EDGE / long_edge;
        w *= scale;
        h *= scale;
    }
    if w * h > MAX_PIXELS {
        let scale = (MAX_PIXELS / (w * h)).sqrt();
        w *= scale;
        h *= scale;
    }
    ((w * h) / PIXELS_PER_TOKEN).ceil() as u64
}

/// Decodes a prefix of `base64_data` and reads `(width, height)` from a PNG, JPEG,
/// GIF or WebP (VP8X) header.
pub fn image_dimensions(base64_data: &str) -> Option<(u32, u32)> {
    let bytes = decode_base64_prefix(base64_data)?;
    if bytes.starts_with(&PNG_SIGNATURE) {
        let width = u32_be(&bytes, 16)?;
        let height = u32_be(&bytes, 20)?;
        return non_zero(width, height);
    }
    if bytes.starts_with(&[0xFF, 0xD8]) {
        return jpeg_dimensions(&bytes);
    }
    if bytes.starts_with(b"GIF8") {
        let width = u32::from(u16_le(&bytes, 6)?);
        let height = u32::from(u16_le(&bytes, 8)?);
        return non_zero(width, height);
    }
    if bytes.starts_with(b"RIFF") && bytes.get(8..16) == Some(b"WEBPVP8X") {
        let width = u24_le(&bytes, 24)?.checked_add(1)?;
        let height = u24_le(&bytes, 27)?.checked_add(1)?;
        return non_zero(width, height);
    }
    None
}

fn jpeg_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    let mut pos = 2usize;
    while *bytes.get(pos)? == 0xFF {
        while bytes.get(pos.checked_add(1)?) == Some(&0xFF) {
            pos = pos.checked_add(1)?;
        }
        let marker = *bytes.get(pos.checked_add(1)?)?;
        if matches!(marker, 0xC0..=0xCF) && !matches!(marker, 0xC4 | 0xC8 | 0xCC) {
            let height = u32::from(u16_be(bytes, pos.checked_add(5)?)?);
            let width = u32::from(u16_be(bytes, pos.checked_add(7)?)?);
            return non_zero(width, height);
        }
        let seg_len = u16_be(bytes, pos.checked_add(2)?)?;
        if seg_len < 2 {
            return None;
        }
        pos = pos.checked_add(2)?.checked_add(usize::from(seg_len))?;
    }
    None
}

fn non_zero(width: u32, height: u32) -> Option<(u32, u32)> {
    (width > 0 && height > 0).then_some((width, height))
}

fn u16_be(bytes: &[u8], offset: usize) -> Option<u16> {
    let &[b0, b1] = bytes.get(offset..offset.checked_add(2)?)? else {
        return None;
    };
    Some(u16::from_be_bytes([b0, b1]))
}

fn u16_le(bytes: &[u8], offset: usize) -> Option<u16> {
    let &[b0, b1] = bytes.get(offset..offset.checked_add(2)?)? else {
        return None;
    };
    Some(u16::from_le_bytes([b0, b1]))
}

fn u24_le(bytes: &[u8], offset: usize) -> Option<u32> {
    let &[b0, b1, b2] = bytes.get(offset..offset.checked_add(3)?)? else {
        return None;
    };
    Some(u32::from_le_bytes([b0, b1, b2, 0]))
}

fn u32_be(bytes: &[u8], offset: usize) -> Option<u32> {
    let &[b0, b1, b2, b3] = bytes.get(offset..offset.checked_add(4)?)? else {
        return None;
    };
    Some(u32::from_be_bytes([b0, b1, b2, b3]))
}

fn b64_val(byte: u8) -> Option<u8> {
    match byte {
        b'A'..=b'Z' => Some(byte.wrapping_sub(b'A')),
        b'a'..=b'z' => Some(byte.wrapping_sub(b'a').wrapping_add(26)),
        b'0'..=b'9' => Some(byte.wrapping_sub(b'0').wrapping_add(52)),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}

fn decode_base64_prefix(input: &str) -> Option<Vec<u8>> {
    let raw = input.as_bytes();
    let capped = raw.get(..MAX_BASE64_PREFIX).unwrap_or(raw);
    let (chunks, _) = capped.as_chunks::<4>();
    if chunks.is_empty() {
        return None;
    }
    let mut out = Vec::with_capacity(chunks.len().saturating_mul(3));
    let mut iter = chunks.iter();
    while let Some(&[c0, c1, c2, c3]) = iter.next() {
        let a = b64_val(c0)?;
        let b = b64_val(c1)?;
        out.push((a << 2) | (b >> 4));
        if c2 == b'=' {
            if c3 != b'=' || iter.next().is_some() {
                return None;
            }
            break;
        }
        let c = b64_val(c2)?;
        out.push((b << 4) | (c >> 2));
        if c3 == b'=' {
            if iter.next().is_some() {
                return None;
            }
            break;
        }
        let d = b64_val(c3)?;
        out.push((c << 6) | d);
    }
    Some(out)
}
