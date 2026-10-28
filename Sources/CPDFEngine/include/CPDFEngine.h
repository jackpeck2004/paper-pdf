#ifndef PAPER_PDF_ENGINE_H
#define PAPER_PDF_ENGINE_H
#include <stddef.h>
#include <stdint.h>
typedef struct PEEngine PEEngine;
typedef struct { float x0,y0,x1,y1; } PERect;
typedef struct { float x,y; } PEPoint;
typedef struct { unsigned char *data; size_t count; } PEBytes;
typedef struct {
    PERect bounds;
    float baseline, size;
    uint32_t color;
    int editable;
    char text[8192];
    char font[256];
} PETextLine;
const char *pe_line_text(const PETextLine *);
const char *pe_line_font(const PETextLine *);
typedef struct { PETextLine *items; int count; } PELines;
// All functions are called on one serial queue. Returned buffers are caller-owned.
PEEngine *pe_open(const unsigned char *, size_t, const char *password, char *error, size_t capacity);
PEEngine *pe_blank(char *error, size_t capacity);
void pe_close(PEEngine *);
const char *pe_error(PEEngine *);
void pe_free(void *);
int pe_page_count(PEEngine *);
int pe_can_modify(PEEngine *);
int pe_is_signed(PEEngine *);
int pe_snapshot(PEEngine *, PEBytes *);
int pe_export(PEEngine *, const char *password, int flatten, int compress, PEBytes *);
int pe_lines(PEEngine *, int page, PELines *);
int pe_replace_line(PEEngine *, int page, int line, const char *text, const char *font, float size, uint32_t color);
// Geometry is MuPDF page space: top-left origin, rotated crop-box bounds.
int pe_annotate(PEEngine *, int page, const char *kind, PERect, const PERect *quads, int count, const char *contents, uint32_t color, float size, const PEPoint *points, int point_count);
int pe_annotation_contents(PEEngine *, int page, int annotation, const char *contents, int remove);
int pe_annotation_rect(PEEngine *, int page, int annotation, PERect);
int pe_rotate(PEEngine *, int page, int degrees);
int pe_crop(PEEngine *, int page, PERect);
int pe_reorder(PEEngine *, const int *pages, int count);
int pe_insert_pdf(PEEngine *, const unsigned char *, size_t, int at);
int pe_insert_blank(PEEngine *, int at);
typedef struct { PERect bounds; int editable; } PEImage;
typedef struct { PEImage *items; int count; } PEImages;
int pe_images(PEEngine *, int page, PEImages *);
int pe_edit_image(PEEngine *, int page, int image, PERect destination, const unsigned char *replacement, size_t count, int remove);
int pe_edit_link(PEEngine *, int page, int index, PERect, const char *uri, int remove);
int pe_image(PEEngine *, int page, PERect, const unsigned char *, size_t);
int pe_redact(PEEngine *, int page, PERect);
int pe_form(PEEngine *, int page, int index, const char *value);
int pe_link(PEEngine *, int page, PERect, const char *uri);
int pe_bookmark(PEEngine *, int page, const char *title, int remove_index);
int pe_ocr_text(PEEngine *, int page, PERect, const char *text);
int pe_extract(PEEngine *, const int *pages, int count, PEBytes *);
#endif
