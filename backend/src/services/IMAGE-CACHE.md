# Image Caching Feature

## Overview

This feature automatically caches images fetched from external sources to reduce dependency on third-party servers and improve performance.

## How it works

1. **Automatic Caching**: When the scraper fetches images from product pages or direct image links, they are automatically optimized and cached locally.

2. **Image Optimization**: Images are automatically converted to progressive JPEG format with 75% quality to reduce file size while maintaining visual quality.

3. **Cache Size Management**: The cache respects a configurable maximum size limit (default: 200MB). When the limit is exceeded:
   - Oldest unused images are deleted first
   - The deletion is logged with information about freed space
   - Newly cached images are prioritized over old ones

4. **Automatic Cleanup**: Images that haven't been accessed for a configurable period (default: 30 days) are automatically deleted.

5. **Unique Identification**: Each cached image is identified by a SHA256 hash of its URL, ensuring the same image isn't cached twice.

## Configuration

Add these environment variables to your `.env` file:

```bash
# Directory where cached images are stored
IMAGE_CACHE_DIR=data/image-cache

# Maximum cache size in bytes (default: 200MB)
# Example values:
# 100MB: 104857600
# 200MB: 209715200
# 500MB: 524288000
# 1GB:   1073741824
IMAGE_CACHE_MAX_SIZE=209715200

# Days before deleting unused cached images (default: 30)
IMAGE_CACHE_MAX_AGE=30
```

## API

The cached images are served via the `/_cache/<hash>` endpoint with:
- Proper JPEG content type
- Immutable cache headers (1 year)
- Automatic access time tracking

## Benefits

- **Server Independence**: Reduces reliance on external image servers that might go offline
- **Performance**: Cached images load faster for subsequent requests
- **Bandwidth**: JPEG optimization reduces bandwidth usage
- **Storage Control**: Configurable limits prevent disk space issues

## Logging

The image cache logs important operations:
- Successful image caching with URL and size
- Cleanup of expired images
- Cache size enforcement with freed space information
- Any errors during image optimization or caching
