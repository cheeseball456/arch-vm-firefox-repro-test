/* Minimal reproduction for the zink/nvk SIGBUS bug.
 * Headless EGL + OpenGL, no window system, no browser.
 * Uploads a single 8192x8192 RGBA8 texture (268,435,456 bytes = the
 * exact size seen in the Firefox crash) via glTexImage2D.
 *
 * Build: gcc -o mesa_repro mesa_repro.c -lEGL -lGL
 * Run:   MESA_LOADER_DRIVER_OVERRIDE=zink ./mesa_repro
 */
#include <EGL/egl.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) { fprintf(stderr, "eglGetDisplay failed\n"); return 1; }

    EGLint major, minor;
    if (!eglInitialize(dpy, &major, &minor)) { fprintf(stderr, "eglInitialize failed\n"); return 1; }
    printf("EGL %d.%d initialized\n", major, minor);

    static const EGLint config_attribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig config;
    EGLint num_configs;
    if (!eglChooseConfig(dpy, config_attribs, &config, 1, &num_configs) || num_configs == 0) {
        fprintf(stderr, "eglChooseConfig failed\n"); return 1;
    }

    eglBindAPI(EGL_OPENGL_API);

    static const EGLint ctx_attribs[] = {
        EGL_CONTEXT_MAJOR_VERSION, 4,
        EGL_CONTEXT_MINOR_VERSION, 6,
        EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
        EGL_NONE
    };
    EGLContext ctx = eglCreateContext(dpy, config, EGL_NO_CONTEXT, ctx_attribs);
    if (ctx == EGL_NO_CONTEXT) { fprintf(stderr, "eglCreateContext failed\n"); return 1; }

    /* 1x1 pbuffer surface -- we only need a current context, not real rendering */
    static const EGLint pbuf_attribs[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
    EGLSurface surf = eglCreatePbufferSurface(dpy, config, pbuf_attribs);
    if (surf == EGL_NO_SURFACE) { fprintf(stderr, "eglCreatePbufferSurface failed\n"); return 1; }

    if (!eglMakeCurrent(dpy, surf, surf, ctx)) { fprintf(stderr, "eglMakeCurrent failed\n"); return 1; }

    printf("GL_VENDOR:   %s\n", glGetString(GL_VENDOR));
    printf("GL_RENDERER: %s\n", glGetString(GL_RENDERER));
    printf("GL_VERSION:  %s\n", glGetString(GL_VERSION));

    const int W = 8192, H = 8192; /* W*H*4 = 268,435,456 bytes, matches the crash */
    size_t size = (size_t)W * H * 4;
    printf("Allocating %zu bytes (%.0f MB) of texture data...\n", size, size / (1024.0 * 1024.0));
    unsigned char *data = malloc(size);
    if (!data) { fprintf(stderr, "malloc failed\n"); return 1; }
    memset(data, 0x7F, size);

    GLuint tex;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);

    printf("Calling glTexImage2D(%dx%d RGBA8)...\n", W, H);
    fflush(stdout); /* flush before the potentially-fatal call */

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    glFinish();

    GLenum err = glGetError();
    printf("glTexImage2D completed. glGetError() = 0x%x\n", err);
    printf("No crash -- bug NOT reproduced via this minimal path.\n");

    free(data);
    return 0;
}
