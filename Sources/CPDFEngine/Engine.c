// SPDX-License-Identifier: MIT
#include "CPDFEngine.h"
#include <mupdf/fitz.h>
#include <mupdf/pdf.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>

struct PEEngine { fz_context *ctx; pdf_document *doc; char error[1024]; };
#define CTX fz_context *ctx = e->ctx
#define TRY e->error[0]=0; fz_try(ctx)
#define CATCH fz_catch(ctx) { snprintf(e->error,sizeof(e->error),"%s",fz_caught_message(ctx)); return 0; } return 1
static fz_rect rect(PERect r) { return fz_make_rect(r.x0,r.y0,r.x1,r.y1); }
static PERect per(fz_rect r) { return (PERect){r.x0,r.y0,r.x1,r.y1}; }
static void rgb(uint32_t v,float c[3]) { c[0]=((v>>16)&255)/255.f; c[1]=((v>>8)&255)/255.f; c[2]=(v&255)/255.f; }
void pe_free(void *p) { free(p); }
const char *pe_error(PEEngine *e) { return e->error; }
void pe_close(PEEngine *e) { if(e) { pdf_drop_document(e->ctx,e->doc); fz_drop_context(e->ctx); free(e); } }
PEEngine *pe_open(const unsigned char *data,size_t count,const char *password,char *error,size_t cap) {
    PEEngine *e=calloc(1,sizeof(*e)); if(!e) return NULL;
    e->ctx=fz_new_context(NULL,NULL,128<<20); if(!e->ctx) { free(e); return NULL; }
    CTX; fz_stream *s=NULL; fz_buffer *b=NULL; fz_var(s); fz_var(b);
    fz_try(ctx) {
        b=fz_new_buffer_from_copied_data(ctx,data,count); s=fz_open_buffer(ctx,b);
        e->doc=pdf_open_document_with_stream(ctx,s);
        if(pdf_needs_password(ctx,e->doc) && !pdf_authenticate_password(ctx,e->doc,password?password:""))
            fz_throw(ctx,FZ_ERROR_ARGUMENT,"Password required or incorrect.");
        // Never execute embedded PDF JavaScript.
        if(pdf_count_pages(ctx,e->doc)<1) fz_throw(ctx,FZ_ERROR_ARGUMENT,"The PDF has no pages.");
    } fz_always(ctx) { fz_drop_stream(ctx,s); fz_drop_buffer(ctx,b); }
    fz_catch(ctx) { snprintf(error,cap,"%s",fz_caught_message(ctx)); pe_close(e); return NULL; }
    return e;
}
static void blank_page(fz_context *ctx,pdf_document *doc,int at) {
    pdf_obj *obj=pdf_add_page(ctx,doc,fz_make_rect(0,0,595,842),0,NULL,NULL);
    fz_try(ctx) { pdf_insert_page(ctx,doc,at,obj); }
    fz_always(ctx) { pdf_drop_obj(ctx,obj); } fz_catch(ctx) { fz_rethrow(ctx); }
}
PEEngine *pe_blank(char *error,size_t cap) {
    PEEngine *e=calloc(1,sizeof(*e)); if(!e) return NULL;
    e->ctx=fz_new_context(NULL,NULL,128<<20); if(!e->ctx) { free(e); return NULL; }
    CTX; fz_try(ctx) { e->doc=pdf_create_document(ctx); blank_page(ctx,e->doc,0); }
    fz_catch(ctx) { snprintf(error,cap,"%s",fz_caught_message(ctx)); pe_close(e); return NULL; }
    return e;
}
int pe_page_count(PEEngine *e) { CTX; int n=0; fz_try(ctx) { n=pdf_count_pages(ctx,e->doc); } fz_catch(ctx) { return 0; } return n; }
int pe_can_modify(PEEngine *e) { CTX; int n=0; fz_try(ctx) { n=pdf_has_permission(ctx,e->doc,FZ_PERMISSION_EDIT); } fz_catch(ctx) { return 0; } return n; }
int pe_is_signed(PEEngine *e) {
    CTX; int signed_doc=0; pdf_page *p=NULL; fz_var(p);
    fz_try(ctx) { for(int i=0;i<pdf_count_pages(ctx,e->doc);i++) {
        p=pdf_load_page(ctx,e->doc,i);
        for(pdf_annot *w=pdf_first_widget(ctx,p);w;w=pdf_next_widget(ctx,w))
            if(pdf_widget_type(ctx,w)==PDF_WIDGET_TYPE_SIGNATURE && pdf_widget_is_signed(ctx,w)) signed_doc=1;
        fz_drop_page(ctx,(fz_page*)p); p=NULL;
    } } fz_always(ctx) { fz_drop_page(ctx,(fz_page*)p); } fz_catch(ctx) { return 1; } return signed_doc;
}
static void write_bytes(fz_context *ctx,pdf_document *doc,pdf_write_options *opts,PEBytes *out) {
    fz_buffer *b=NULL; fz_output *o=NULL; fz_var(b); fz_var(o); out->data=NULL; out->count=0;
    fz_try(ctx) {
        b=fz_new_buffer(ctx,4096); o=fz_new_output_with_buffer(ctx,b);
        pdf_write_document(ctx,doc,o,opts); fz_close_output(ctx,o);
        unsigned char *p; size_t n=fz_buffer_storage(ctx,b,&p);
        out->data=malloc(n); if(!out->data) fz_throw(ctx,FZ_ERROR_SYSTEM,"Out of memory");
        memcpy(out->data,p,n); out->count=n;
    } fz_always(ctx) { fz_drop_output(ctx,o); fz_drop_buffer(ctx,b); } fz_catch(ctx) { fz_rethrow(ctx); }
}
int pe_snapshot(PEEngine *e,PEBytes *out) {
    CTX; TRY { pdf_write_options o=pdf_default_write_options; o.do_incremental=0; o.do_garbage=3; o.do_compress=1; o.do_encrypt=PDF_ENCRYPT_NONE; write_bytes(ctx,e->doc,&o,out); } CATCH;
}
int pe_export(PEEngine *e,const char *password,int flatten,int compress,PEBytes *out) {
    CTX; PEBytes b={0}; PEEngine *copy=NULL; fz_var(copy); fz_var(b.data);
    TRY {
        if(!pe_snapshot(e,&b)) fz_throw(ctx,FZ_ERROR_GENERIC,"%s",e->error);
        char error[1024]; copy=pe_open(b.data,b.count,"",error,sizeof(error));
        if(!copy) fz_throw(ctx,FZ_ERROR_GENERIC,"%s",error);
        // A separate context must catch its own exceptions.
        fz_context *cc=copy->ctx;
        fz_try(cc) {
            if(flatten) pdf_bake_document(cc,copy->doc,1,1);
            if(compress) {
                pdf_image_rewriter_options img={0};
                img.color_lossless_image_subsample_threshold=225; img.color_lossless_image_subsample_to=150;
                img.color_lossy_image_subsample_threshold=225; img.color_lossy_image_subsample_to=150;
                img.gray_lossless_image_subsample_threshold=225; img.gray_lossless_image_subsample_to=150;
                img.gray_lossy_image_subsample_threshold=225; img.gray_lossy_image_subsample_to=150;
                pdf_rewrite_images(cc,copy->doc,&img);
            }
            pdf_write_options o=pdf_default_write_options; o.do_incremental=0; o.do_garbage=3;
            o.do_compress=1; o.do_compress_images=1; o.do_compress_fonts=1; o.do_encrypt=PDF_ENCRYPT_NONE;
            if(password && *password) {
                if(strlen(password)>127) fz_throw(cc,FZ_ERROR_ARGUMENT,"Password must fit in 127 UTF-8 bytes.");
                o.do_encrypt=PDF_ENCRYPT_AES_256; o.permissions=~0;
                snprintf(o.upwd_utf8,sizeof(o.upwd_utf8),"%s",password); snprintf(o.opwd_utf8,sizeof(o.opwd_utf8),"%s",password);
            }
            write_bytes(cc,copy->doc,&o,out);
        } fz_catch(cc) { snprintf(copy->error,sizeof(copy->error),"%s",fz_caught_message(cc)); }
        if(copy->error[0]) fz_throw(ctx,FZ_ERROR_GENERIC,"%s",copy->error);
    } fz_always(ctx) { free(b.data); pe_close(copy); } CATCH;
}
static fz_stext_page *text_page(fz_context *ctx,pdf_page *p) {
    fz_stext_options opts={0}; opts.flags=FZ_STEXT_PRESERVE_WHITESPACE;
    fz_stext_page *text=fz_new_stext_page(ctx,pdf_bound_page(ctx,p,FZ_CROP_BOX));
    fz_device *dev=NULL; fz_var(dev);
    fz_try(ctx) { dev=fz_new_stext_device(ctx,text,&opts); pdf_run_page_contents(ctx,p,dev,fz_identity,NULL); fz_close_device(ctx,dev); }
    fz_always(ctx) { fz_drop_device(ctx,dev); } fz_catch(ctx) { fz_drop_stext_page(ctx,text); fz_rethrow(ctx); }
    return text;
}
static void line_info(fz_context *ctx,fz_stext_line *l,PETextLine *r) {
    memset(r,0,sizeof(*r)); r->bounds=per(l->bbox); fz_stext_char *a=l->first_char;
    if(!a) return;
    r->baseline=a->origin.y; r->size=a->size; r->color=a->argb&0xffffff;
    snprintf(r->font,sizeof(r->font),"%s",fz_font_name(ctx,a->font));
    r->editable=!l->wmode && fabsf(l->dir.x-1)<.001 && fabsf(l->dir.y)<.001;
    size_t len=0;
    for(fz_stext_char *c=a;c;c=c->next) {
        char u[8]; int n=fz_runetochar(u,c->c);
        if(len+n>=sizeof(r->text)) { r->editable=0; break; }
        memcpy(r->text+len,u,n); len+=n;
        if(c->font!=a->font || fabsf(c->size-a->size)>.1 || c->argb!=a->argb || c->bidi%2 || (c->flags&FZ_STEXT_SYNTHETIC)) r->editable=0;
    }
    r->text[len]=0;
}
int pe_lines(PEEngine *e,int page,PELines *out) {
    CTX; pdf_page *p=NULL; fz_stext_page *t=NULL; fz_var(p); fz_var(t); out->items=NULL; out->count=0;
    TRY {
        p=pdf_load_page(ctx,e->doc,page); t=text_page(ctx,p);
        int n=0; for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_TEXT) for(fz_stext_line *l=b->u.t.first_line;l;l=l->next) n++;
        out->items=calloc(n?n:1,sizeof(PETextLine)); if(!out->items) fz_throw(ctx,FZ_ERROR_SYSTEM,"Out of memory");
        for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_TEXT) for(fz_stext_line *l=b->u.t.first_line;l;l=l->next) line_info(ctx,l,&out->items[out->count++]);
    } fz_always(ctx) { fz_drop_stext_page(ctx,t); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
static void append_text(fz_context *ctx,pdf_document *doc,pdf_page *page,fz_text *text,uint32_t color,int invisible) {
    pdf_obj *res=NULL,*stream=NULL; fz_buffer *buf=NULL; fz_device *dev=NULL;
    fz_var(res); fz_var(stream); fz_var(buf); fz_var(dev);
    fz_try(ctx) {
        res=pdf_copy_dict(ctx,pdf_dict_get_inheritable(ctx,page->obj,PDF_NAME(Resources)));
        if(!res) res=pdf_new_dict(ctx,doc,4);
        buf=fz_new_buffer(ctx,256); fz_rect box; fz_matrix ctm;
        pdf_page_transform(ctx,page,&box,&ctm);
        dev=pdf_new_pdf_device(ctx,doc,fz_invert_matrix(ctm),res,buf);
        float c[3]; rgb(color,c);
        if(invisible) fz_ignore_text(ctx,dev,text,fz_identity);
        else fz_fill_text(ctx,dev,text,fz_identity,fz_device_rgb(ctx),c,1,fz_default_color_params);
        fz_close_device(ctx,dev);
        pdf_dict_put(ctx,page->obj,PDF_NAME(Resources),res);
        stream=pdf_add_stream(ctx,doc,buf,NULL,0);
        pdf_obj *contents=pdf_dict_get(ctx,page->obj,PDF_NAME(Contents));
        pdf_obj *array=pdf_new_array(ctx,doc,2);
        if(pdf_is_array(ctx,contents)) for(int i=0;i<pdf_array_len(ctx,contents);i++) pdf_array_push(ctx,array,pdf_array_get(ctx,contents,i));
        else if(contents) pdf_array_push(ctx,array,contents);
        pdf_array_push(ctx,array,stream); pdf_dict_put_drop(ctx,page->obj,PDF_NAME(Contents),array);
    } fz_always(ctx) { fz_drop_device(ctx,dev); fz_drop_buffer(ctx,buf); pdf_drop_obj(ctx,res); pdf_drop_obj(ctx,stream); } fz_catch(ctx) { fz_rethrow(ctx); }
}
int pe_replace_line(PEEngine *e,int page,int index,const char *replacement,const char *font_name,float size,uint32_t color) {
    CTX; pdf_page *p=NULL; fz_stext_page *t=NULL; fz_font *font=NULL; fz_text *text=NULL; pdf_annot *red=NULL;
    fz_var(p); fz_var(t); fz_var(font); fz_var(text); fz_var(red);
    TRY {
        p=pdf_load_page(ctx,e->doc,page); t=text_page(ctx,p); fz_stext_line *target=NULL; int n=0;
        for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_TEXT) for(fz_stext_line *l=b->u.t.first_line;l;l=l->next) if(n++==index) target=l;
        if(!target || !target->first_char) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Text selection is no longer available.");
        PETextLine info; line_info(ctx,target,&info);
        if(!info.editable) fz_throw(ctx,FZ_ERROR_ARGUMENT,"This line has mixed styles, rotated text, or complex writing. It cannot be safely corrected.");
        if(size<1 || size>500 || strchr(replacement,'\n') || strchr(replacement,'\r')) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Use a single line and a font size between 1 and 500 points.");
        font=font_name && *font_name ? fz_new_base14_font(ctx,font_name) : fz_keep_font(ctx,target->first_char->font);
        for(const char *s=replacement;*s;) { int rune; s+=fz_chartorune(&rune,s); if(!fz_encode_character(ctx,font,rune)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"The selected font does not contain a replacement character. Choose Helvetica, Times-Roman, or Courier, or use a text annotation."); }
        text=fz_new_text(ctx); fz_point origin=target->first_char->origin;
        fz_matrix trm=fz_make_matrix(size,0,0,-size,origin.x,origin.y);
        fz_show_string(ctx,text,font,trm,replacement,0,0,FZ_BIDI_LTR,FZ_LANG_UNSET);
        fz_rect newbox=fz_bound_text(ctx,text,NULL,fz_identity); fz_rect bounds=pdf_bound_page(ctx,p,FZ_CROP_BOX);
        if(newbox.x1>bounds.x1 || newbox.y1>bounds.y1 || newbox.x0<bounds.x0 || newbox.y0<bounds.y0) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Replacement text does not fit on the page.");
        // Reject edits that would erase adjacent lines, or overlap other text after replacement.
        for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_TEXT) for(fz_stext_line *l=b->u.t.first_line;l;l=l->next) if(l!=target) {
            fz_rect collision=fz_intersect_rect(newbox,l->bbox);
            if(!fz_is_empty_rect(collision)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Replacement would overlap another line. Shorten the correction or reduce its size.");
            for(fz_stext_char *c=l->first_char;c;c=c->next) if(!fz_is_empty_rect(fz_intersect_rect(target->bbox,fz_rect_from_quad(c->quad)))) fz_throw(ctx,FZ_ERROR_ARGUMENT,"The source line overlaps other text and cannot be safely replaced.");
        }
        for(pdf_annot *a=pdf_first_annot(ctx,p);a;a=pdf_next_annot(ctx,a))
            if(pdf_annot_type(ctx,a)==PDF_ANNOT_REDACT) fz_throw(ctx,FZ_ERROR_ARGUMENT,"This page already has pending redactions. Apply or remove them in the originating app before correcting text.");
        red=pdf_create_annot(ctx,p,PDF_ANNOT_REDACT); pdf_set_annot_rect(ctx,red,target->bbox);
        pdf_redact_options opts={0}; opts.image_method=PDF_REDACT_IMAGE_NONE; opts.line_art=PDF_REDACT_LINE_ART_NONE; opts.text=PDF_REDACT_TEXT_REMOVE;
        pdf_redact_page(ctx,e->doc,p,&opts); append_text(ctx,e->doc,p,text,color,0);
    } fz_always(ctx) { pdf_drop_annot(ctx,red); fz_drop_text(ctx,text); fz_drop_font(ctx,font); fz_drop_stext_page(ctx,t); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_annotate(PEEngine *e,int page,const char *kind,PERect r,const PERect *quads,int count,const char *contents,uint32_t color,float size,const PEPoint *points,int point_count) {
    CTX; pdf_page *p=NULL; pdf_annot *a=NULL; fz_quad *q=NULL; fz_point *v=NULL; fz_var(p); fz_var(a); fz_var(q); fz_var(v);
    TRY {
        enum pdf_annot_type type=pdf_annot_type_from_string(ctx,kind);
        if(type==PDF_ANNOT_UNKNOWN) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Unknown annotation tool.");
        p=pdf_load_page(ctx,e->doc,page); a=pdf_create_annot(ctx,p,type); float c[3]; rgb(color,c);
        if(type!=PDF_ANNOT_LINE && type!=PDF_ANNOT_INK && type!=PDF_ANNOT_HIGHLIGHT && type!=PDF_ANNOT_UNDERLINE && type!=PDF_ANNOT_STRIKE_OUT) pdf_set_annot_rect(ctx,a,rect(r));
        pdf_set_annot_color(ctx,a,3,c); pdf_set_annot_contents(ctx,a,contents?contents:"");
        pdf_set_annot_flags(ctx,a,PDF_ANNOT_IS_PRINT);
        if(type==PDF_ANNOT_HIGHLIGHT || type==PDF_ANNOT_UNDERLINE || type==PDF_ANNOT_STRIKE_OUT) {
            if(count<1) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Select text first.");
            q=calloc(count,sizeof(fz_quad)); if(!q) fz_throw(ctx,FZ_ERROR_SYSTEM,"Out of memory");
            for(int i=0;i<count;i++) q[i]=fz_quad_from_rect(rect(quads[i]));
            pdf_set_annot_quad_points(ctx,a,count,q);
        }
        if(type==PDF_ANNOT_FREE_TEXT) {
            // FreeText /C paints the box background, while /DA colors the glyphs.
            // Sharing the color makes the text disappear into a solid rectangle.
            pdf_set_annot_color(ctx,a,0,c);
            pdf_set_annot_border_width(ctx,a,0);
            pdf_set_annot_default_appearance(ctx,a,"Helv",size,3,c);
        }
        if(type==PDF_ANNOT_LINE) { pdf_set_annot_line(ctx,a,point_count>1?fz_make_point(points[0].x,points[0].y):fz_make_point(r.x0,r.y0),point_count>1?fz_make_point(points[point_count-1].x,points[point_count-1].y):fz_make_point(r.x1,r.y1)); pdf_set_annot_line_end_style(ctx,a,PDF_ANNOT_LE_CLOSED_ARROW); }
        if(type==PDF_ANNOT_INK) {
            if(point_count<2) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Draw a stroke first.");
            v=calloc(point_count,sizeof(fz_point)); if(!v) fz_throw(ctx,FZ_ERROR_SYSTEM,"Out of memory");
            for(int i=0;i<point_count;i++) v[i]=fz_make_point(points[i].x,points[i].y);
            pdf_set_annot_ink_list(ctx,a,1,&point_count,v);
        }
        if(type==PDF_ANNOT_SQUARE || type==PDF_ANNOT_CIRCLE || type==PDF_ANNOT_LINE || type==PDF_ANNOT_INK) pdf_set_annot_border_width(ctx,a,1.5);
        pdf_update_annot(ctx,a);
    } fz_always(ctx) { free(q); free(v); pdf_drop_annot(ctx,a); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_annotation_contents(PEEngine *e,int page,int index,const char *contents,int remove) {
    CTX; pdf_page *p=NULL; fz_var(p);
    TRY { p=pdf_load_page(ctx,e->doc,page); pdf_annot *a=pdf_first_annot(ctx,p); for(int i=0;a && i<index;i++) a=pdf_next_annot(ctx,a); if(!a) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Annotation no longer exists."); if(remove) pdf_delete_annot(ctx,p,a); else { pdf_set_annot_contents(ctx,a,contents); pdf_update_annot(ctx,a); } }
    fz_always(ctx) { fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_rotate(PEEngine *e,int page,int degrees) { CTX; TRY { pdf_obj *p=pdf_lookup_page_obj(ctx,e->doc,page); int old=pdf_dict_get_inheritable_int(ctx,p,PDF_NAME(Rotate)); pdf_dict_put_int(ctx,p,PDF_NAME(Rotate),(old+degrees+360)%360); } CATCH; }
int pe_crop(PEEngine *e,int page,PERect r) {
    CTX; pdf_page *p=NULL; fz_var(p); TRY { p=pdf_load_page(ctx,e->doc,page); fz_rect box; fz_matrix m; pdf_page_transform(ctx,p,&box,&m); fz_rect crop=fz_transform_rect(rect(r),fz_invert_matrix(m)); if(fz_is_empty_rect(crop)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Crop must have an area."); pdf_dict_put_rect(ctx,p->obj,PDF_NAME(CropBox),crop); } fz_always(ctx) { fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_reorder(PEEngine *e,const int *pages,int count) {
    CTX; pdf_obj *catalog=NULL,*form=NULL; fz_var(catalog); fz_var(form);
    TRY {
        int n=pdf_count_pages(ctx,e->doc);
        if(count<1) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Keep at least one page.");
        for(int i=0;i<count;i++) {
            if(pages[i]<0||pages[i]>=n) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Invalid page index.");
            for(int j=0;j<i;j++) if(pages[i]==pages[j]) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Use Duplicate Pages to make independent page copies.");
        }
        catalog=pdf_copy_dict(ctx,pdf_dict_get(ctx,pdf_trailer(ctx,e->doc),PDF_NAME(Root)));
        form=pdf_keep_obj(ctx,pdf_dict_get(ctx,catalog,PDF_NAME(AcroForm)));
        pdf_rearrange_pages(ctx,e->doc,count,pages,PDF_CLEAN_STRUCTURE_KEEP);
        pdf_obj *root=pdf_dict_get(ctx,pdf_trailer(ctx,e->doc),PDF_NAME(Root));
        // The clean/rearrange API rebuilds a minimal catalog. Retain unrelated
        // catalog entries, including language, metadata, and accessibility flags.
        for(int i=0;i<pdf_dict_len(ctx,catalog);i++) {
            pdf_obj *key=pdf_dict_get_key(ctx,catalog,i);
            if(pdf_name_eq(ctx,key,PDF_NAME(Pages)) || pdf_name_eq(ctx,key,PDF_NAME(Outlines)) || pdf_name_eq(ctx,key,PDF_NAME(Names)) || pdf_name_eq(ctx,key,PDF_NAME(Dests)) || pdf_name_eq(ctx,key,PDF_NAME(AcroForm)) || pdf_name_eq(ctx,key,PDF_NAME(StructTreeRoot))) continue;
            if(!pdf_dict_get(ctx,root,key)) pdf_dict_put(ctx,root,key,pdf_dict_get_val(ctx,catalog,i));
        }
        pdf_obj *oldnames=pdf_dict_get(ctx,catalog,PDF_NAME(Names));
        if(oldnames) {
            pdf_obj *names=pdf_dict_get(ctx,root,PDF_NAME(Names));
            if(!names) names=pdf_dict_put_dict(ctx,root,PDF_NAME(Names),4);
            for(int i=0;i<pdf_dict_len(ctx,oldnames);i++) {
                pdf_obj *key=pdf_dict_get_key(ctx,oldnames,i);
                if(!pdf_name_eq(ctx,key,PDF_NAME(Dests))) pdf_dict_put(ctx,names,key,pdf_dict_get_val(ctx,oldnames,i));
            }
        }
        if(form) {
            pdf_obj *fields=pdf_new_array(ctx,e->doc,4);
            for(int i=0;i<count;i++) {
                pdf_obj *ann=pdf_dict_get(ctx,pdf_lookup_page_obj(ctx,e->doc,i),PDF_NAME(Annots));
                for(int j=0;j<pdf_array_len(ctx,ann);j++) {
                    pdf_obj *field=pdf_array_get(ctx,ann,j);
                    if(!pdf_name_eq(ctx,pdf_dict_get(ctx,field,PDF_NAME(Subtype)),PDF_NAME(Widget))) continue;
                    int depth=0;
                    while(pdf_dict_get(ctx,field,PDF_NAME(Parent))) {
                        if(++depth>64) fz_throw(ctx,FZ_ERROR_FORMAT,"Cyclic form hierarchy.");
                        field=pdf_dict_get(ctx,field,PDF_NAME(Parent));
                    }
                    int found=0; for(int k=0;k<pdf_array_len(ctx,fields);k++) if(!pdf_objcmp(ctx,field,pdf_array_get(ctx,fields,k))) found=1;
                    if(!found) pdf_array_push(ctx,fields,field);
                }
            }
            pdf_dict_put_drop(ctx,form,PDF_NAME(Fields),fields); pdf_dict_put(ctx,root,PDF_NAME(AcroForm),form);
        }
    } fz_always(ctx) { pdf_drop_obj(ctx,catalog); pdf_drop_obj(ctx,form); } CATCH;
}
int pe_insert_blank(PEEngine *e,int at) { CTX; TRY { blank_page(ctx,e->doc,at); } CATCH; }
int pe_insert_pdf(PEEngine *e,const unsigned char *data,size_t count,int at) {
    CTX; pdf_document *src=NULL; fz_stream *s=NULL; fz_buffer *b=NULL; pdf_graft_map *map=NULL; fz_var(src); fz_var(s); fz_var(b); fz_var(map);
    TRY { b=fz_new_buffer_from_copied_data(ctx,data,count); s=fz_open_buffer(ctx,b); src=pdf_open_document_with_stream(ctx,s); if(pdf_needs_password(ctx,src)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Unlock the inserted PDF before merging it."); map=pdf_new_graft_map(ctx,e->doc);
        for(int i=0;i<pdf_count_pages(ctx,src);i++) {
            pdf_graft_mapped_page(ctx,map,at+i,src,i);
            // MuPDF's page graft deliberately excludes annotations. Copy non-widget annotations too.
            pdf_obj *old=pdf_lookup_page_obj(ctx,src,i), *dest=pdf_lookup_page_obj(ctx,e->doc,at+i);
            pdf_obj *ann=pdf_dict_get(ctx,old,PDF_NAME(Annots));
            if(pdf_array_len(ctx,ann)) {
                pdf_obj *list=pdf_new_array(ctx,e->doc,0); pdf_dict_put_drop(ctx,dest,PDF_NAME(Annots),list);
                for(int j=0;j<pdf_array_len(ctx,ann);j++) {
                    pdf_obj *a=pdf_array_get(ctx,ann,j);
                    if(pdf_name_eq(ctx,pdf_dict_get(ctx,a,PDF_NAME(Subtype)),PDF_NAME(Popup))) continue;
                    if(pdf_name_eq(ctx,pdf_dict_get(ctx,a,PDF_NAME(Subtype)),PDF_NAME(Link))) continue;
                    if(pdf_name_eq(ctx,pdf_dict_get(ctx,a,PDF_NAME(Subtype)),PDF_NAME(Widget))) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Merging PDFs with form fields is not supported yet; export a flattened copy first.");
                    // P points back to the source page tree; omit it while grafting.
                    pdf_obj *dict=pdf_copy_dict(ctx,a); pdf_dict_del(ctx,dict,PDF_NAME(P)); pdf_dict_del(ctx,dict,PDF_NAME(Popup));
                    pdf_obj *copy=pdf_graft_mapped_object(ctx,map,dict); pdf_drop_obj(ctx,dict);
                    pdf_dict_put(ctx,copy,PDF_NAME(P),dest); pdf_array_push_drop(ctx,list,copy);
                }
            }
        }
        for(int i=0;i<pdf_count_pages(ctx,src);i++) {
            pdf_page *source_page=pdf_load_page(ctx,src,i);
            fz_link *links=NULL; fz_var(links);
            fz_try(ctx) {
                links=pdf_load_links(ctx,source_page);
                for(fz_link *l=links;l;l=l->next) {
                    char uri[128]; const char *target=l->uri;
                    if(!target) continue;
                    if(!fz_is_external_link(ctx,target)) {
                        int destination=pdf_resolve_link(ctx,src,target,NULL,NULL);
                        if(destination<0 || destination>=pdf_count_pages(ctx,src)) continue;
                        snprintf(uri,sizeof(uri),"#page=%d",at+destination+1); target=uri;
                    }
                    if(!pe_link(e,at+i,per(l->rect),target)) fz_throw(ctx,FZ_ERROR_GENERIC,"%s",e->error);
                }
            } fz_always(ctx) { fz_drop_link(ctx,links); fz_drop_page(ctx,(fz_page*)source_page); } fz_catch(ctx) { fz_rethrow(ctx); }
        }
    } fz_always(ctx) { pdf_drop_graft_map(ctx,map); pdf_drop_document(ctx,src); fz_drop_stream(ctx,s); fz_drop_buffer(ctx,b); } CATCH;
}
int pe_image(PEEngine *e,int page,PERect r,const unsigned char *data,size_t count) {
    CTX; pdf_page *p=NULL; fz_image *img=NULL; fz_buffer *b=NULL; pdf_annot *a=NULL; fz_var(p); fz_var(img); fz_var(b); fz_var(a);
    TRY { p=pdf_load_page(ctx,e->doc,page); b=fz_new_buffer_from_copied_data(ctx,data,count); img=fz_new_image_from_buffer(ctx,b); a=pdf_create_annot(ctx,p,PDF_ANNOT_STAMP); pdf_set_annot_rect(ctx,a,rect(r)); pdf_set_annot_stamp_image(ctx,a,img); pdf_set_annot_flags(ctx,a,PDF_ANNOT_IS_PRINT); pdf_update_annot(ctx,a); }
    fz_always(ctx) { pdf_drop_annot(ctx,a); fz_drop_image(ctx,img); fz_drop_buffer(ctx,b); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_redact(PEEngine *e,int page,PERect r) {
    CTX; pdf_page *p=NULL; pdf_annot *a=NULL; fz_var(p); fz_var(a);
    TRY { p=pdf_load_page(ctx,e->doc,page);
        for(pdf_annot *pending=pdf_first_annot(ctx,p);pending;pending=pdf_next_annot(ctx,pending))
            if(pdf_annot_type(ctx,pending)==PDF_ANNOT_REDACT) fz_throw(ctx,FZ_ERROR_ARGUMENT,"This page already has pending redactions. Apply or remove them in the originating app first.");
        a=pdf_create_annot(ctx,p,PDF_ANNOT_REDACT); pdf_set_annot_rect(ctx,a,rect(r)); pdf_redact_options opts={1,PDF_REDACT_IMAGE_REMOVE,PDF_REDACT_LINE_ART_REMOVE_IF_TOUCHED,PDF_REDACT_TEXT_REMOVE}; pdf_redact_page(ctx,e->doc,p,&opts); }
    fz_always(ctx) { pdf_drop_annot(ctx,a); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_form(PEEngine *e,int page,int index,const char *value) {
    CTX; pdf_page *p=NULL; fz_var(p);
    TRY { p=pdf_load_page(ctx,e->doc,page); pdf_annot *w=pdf_first_widget(ctx,p); for(int i=0;w && i<index;i++) w=pdf_next_widget(ctx,w); if(!w || pdf_widget_is_readonly(ctx,w)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"This field is read-only or unavailable.");
        if(pdf_widget_type(ctx,w)==PDF_WIDGET_TYPE_SIGNATURE) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Certificate signatures are not supported. Use a visual signature instead.");
        if(!pdf_set_annot_field_value(ctx,e->doc,w,value,1)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"The field rejected this value."); pdf_update_page(ctx,p);
    } fz_always(ctx) { fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_link(PEEngine *e,int page,PERect r,const char *uri) {
    CTX; pdf_page *p=NULL; fz_var(p); TRY { p=pdf_load_page(ctx,e->doc,page); fz_link *l=pdf_create_link(ctx,p,rect(r),uri); fz_drop_link(ctx,l); } fz_always(ctx) { fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_bookmark(PEEngine *e,int page,const char *title,int remove_index) {
    CTX; TRY {
        pdf_obj *root=pdf_dict_get(ctx,pdf_trailer(ctx,e->doc),PDF_NAME(Root)); pdf_obj *out=pdf_dict_get(ctx,root,PDF_NAME(Outlines));
        if(!out) { pdf_obj *dict=pdf_new_dict(ctx,e->doc,4); pdf_dict_put(ctx,dict,PDF_NAME(Type),PDF_NAME(Outlines)); out=pdf_add_object_drop(ctx,e->doc,dict); pdf_dict_put_drop(ctx,root,PDF_NAME(Outlines),out); }
        if(remove_index>=0) {
            pdf_obj *item=pdf_dict_get(ctx,out,PDF_NAME(First)); for(int i=0;item && i<remove_index;i++) item=pdf_dict_get(ctx,item,PDF_NAME(Next));
            if(!item) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Bookmark no longer exists.");
            pdf_obj *prev=pdf_dict_get(ctx,item,PDF_NAME(Prev)),*next=pdf_dict_get(ctx,item,PDF_NAME(Next));
            if(prev) pdf_dict_put(ctx,prev,PDF_NAME(Next),next); else pdf_dict_put(ctx,out,PDF_NAME(First),next);
            if(next) pdf_dict_put(ctx,next,PDF_NAME(Prev),prev); else pdf_dict_put(ctx,out,PDF_NAME(Last),prev);
        } else {
            pdf_obj *dict=pdf_new_dict(ctx,e->doc,6); pdf_dict_put_text_string(ctx,dict,PDF_NAME(Title),title); pdf_dict_put(ctx,dict,PDF_NAME(Parent),out);
            pdf_obj *dest=pdf_new_array(ctx,e->doc,2); pdf_array_push(ctx,dest,pdf_lookup_page_obj(ctx,e->doc,page)); pdf_array_push(ctx,dest,PDF_NAME(Fit)); pdf_dict_put_drop(ctx,dict,PDF_NAME(Dest),dest);
            pdf_obj *item=pdf_add_object_drop(ctx,e->doc,dict),*last=pdf_dict_get(ctx,out,PDF_NAME(Last));
            if(last) { pdf_dict_put(ctx,last,PDF_NAME(Next),item); pdf_dict_put(ctx,item,PDF_NAME(Prev),last); } else pdf_dict_put(ctx,out,PDF_NAME(First),item);
            pdf_dict_put(ctx,out,PDF_NAME(Last),item); pdf_drop_obj(ctx,item);
        }
    } CATCH;
}
int pe_ocr_text(PEEngine *e,int page,PERect r,const char *s) {
    CTX; pdf_page *p=NULL; fz_font *font=NULL; fz_text *text=NULL; fz_var(p); fz_var(font); fz_var(text);
    TRY { p=pdf_load_page(ctx,e->doc,page); font=fz_new_base14_font(ctx,"Helvetica"); text=fz_new_text(ctx); float size=r.y1-r.y0;
        fz_matrix m=fz_make_matrix(size,0,0,-size,r.x0,r.y1-size*.2); fz_matrix end=fz_measure_string(ctx,font,m,s,0,0,FZ_BIDI_LTR,FZ_LANG_UNSET);
        float width=end.e-m.e; if(width>0) m.a*= (r.x1-r.x0)/width;
        fz_show_string(ctx,text,font,m,s,0,0,FZ_BIDI_LTR,FZ_LANG_UNSET); append_text(ctx,e->doc,p,text,0,1);
    } fz_always(ctx) { fz_drop_text(ctx,text); fz_drop_font(ctx,font); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_extract(PEEngine *e,const int *pages,int count,PEBytes *out) {
    PEBytes b={0}; if(!pe_snapshot(e,&b)) return 0; char err[1024]; PEEngine *copy=pe_open(b.data,b.count,"",err,sizeof(err)); free(b.data);
    if(!copy) { snprintf(e->error,sizeof(e->error),"%s",err); return 0; }
    int ok=pe_reorder(copy,pages,count) && pe_export(copy,"",0,0,out); if(!ok) snprintf(e->error,sizeof(e->error),"%s",copy->error); pe_close(copy); return ok;
}

int pe_annotation_rect(PEEngine *e,int page,int index,PERect r) {
    CTX; pdf_page *p=NULL; fz_var(p);
    TRY {
        p=pdf_load_page(ctx,e->doc,page); pdf_annot *a=pdf_first_annot(ctx,p);
        for(int i=0;a && i<index;i++) a=pdf_next_annot(ctx,a);
        if(!a) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Annotation no longer exists.");
        enum pdf_annot_type t=pdf_annot_type(ctx,a);
        if(t!=PDF_ANNOT_STAMP && t!=PDF_ANNOT_TEXT && t!=PDF_ANNOT_FREE_TEXT && t!=PDF_ANNOT_SQUARE && t!=PDF_ANNOT_CIRCLE)
            fz_throw(ctx,FZ_ERROR_ARGUMENT,"This annotation has separate geometry and cannot be resized with this tool.");
        pdf_set_annot_rect(ctx,a,rect(r)); pdf_update_annot(ctx,a);
    } fz_always(ctx) { fz_drop_page(ctx,(fz_page*)p); } CATCH;
}

static fz_stext_page *image_page(fz_context *ctx,pdf_page *page) {
    fz_stext_options opts={0}; opts.flags=FZ_STEXT_PRESERVE_IMAGES;
    fz_rect bounds=pdf_bound_page(ctx,page,FZ_CROP_BOX);
    fz_stext_page *text=fz_new_stext_page(ctx,bounds); fz_device *dev=NULL; fz_var(dev);
    fz_try(ctx) { dev=fz_new_stext_device(ctx,text,&opts); pdf_run_page_contents(ctx,page,dev,fz_identity,NULL); fz_close_device(ctx,dev); }
    fz_always(ctx) { fz_drop_device(ctx,dev); } fz_catch(ctx) { fz_drop_stext_page(ctx,text); fz_rethrow(ctx); }
    return text;
}
static int image_editable(fz_stext_block *b) {
    fz_matrix m=b->u.i.transform;
    return fabsf(m.b)<.001 && fabsf(m.c)<.001 && m.a>0 && m.d>0 && !b->u.i.image->imagemask;
}
int pe_images(PEEngine *e,int page,PEImages *out) {
    CTX; pdf_page *p=NULL; fz_stext_page *t=NULL; fz_var(p); fz_var(t); out->items=NULL; out->count=0;
    TRY { p=pdf_load_page(ctx,e->doc,page); t=image_page(ctx,p); int n=0;
        for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_IMAGE) n++;
        out->items=calloc(n?n:1,sizeof(PEImage)); if(!out->items) fz_throw(ctx,FZ_ERROR_SYSTEM,"Out of memory");
        for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_IMAGE) {
            out->items[out->count++]=(PEImage){per(b->bbox),image_editable(b)};
        }
    } fz_always(ctx) { fz_drop_stext_page(ctx,t); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
typedef struct { fz_rect target; fz_matrix pagectm; int removed; fz_image *image; } image_filter_state;
static fz_image *remove_image(fz_context *ctx,void *opaque,fz_matrix ctm,const char *name,fz_image *image,fz_rect scissor) {
    image_filter_state *s=opaque;
    fz_rect b=fz_transform_rect(fz_unit_rect,fz_concat(ctm,s->pagectm));
    if(fabsf(b.x0-s->target.x0)<.1 && fabsf(b.y0-s->target.y0)<.1 && fabsf(b.x1-s->target.x1)<.1 && fabsf(b.y1-s->target.y1)<.1) {
        fz_rect visible=fz_transform_rect(scissor,s->pagectm);
        if(!fz_contains_rect(visible,b)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Clipped images cannot be safely moved or replaced.");
        s->removed++; if(s->removed>1) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Overlapping image instances cannot be safely edited.");
        s->image=fz_keep_image(ctx,image); return NULL;
    }
    return image;
}
int pe_edit_image(PEEngine *e,int page,int index,PERect destination,const unsigned char *replacement,size_t count,int remove) {
    CTX; pdf_page *p=NULL; fz_stext_page *t=NULL; fz_buffer *png=NULL; fz_var(p); fz_var(t); fz_var(png);
    image_filter_state state={0}; fz_var(state.image);
    TRY {
        p=pdf_load_page(ctx,e->doc,page); t=image_page(ctx,p); fz_stext_block *target=NULL; int n=0;
        for(fz_stext_block *b=t->first_block;b;b=b->next) if(b->type==FZ_STEXT_BLOCK_IMAGE && n++==index) target=b;
        if(!target || !image_editable(target)) fz_throw(ctx,FZ_ERROR_ARGUMENT,"This image has a rotation, mask, or unsupported layout and cannot be safely edited.");
        state.target=target->bbox; fz_rect box; pdf_page_transform(ctx,p,&box,&state.pagectm);
        pdf_sanitize_filter_options sanitize={0}; sanitize.opaque=&state; sanitize.image_filter=remove_image;
        pdf_filter_factory factories[]={{pdf_new_sanitize_filter,&sanitize},{NULL,NULL}};
        pdf_filter_options opts={0}; opts.instance_forms=1; opts.filters=factories;
        pdf_filter_page_contents(ctx,e->doc,p,&opts);
        if(state.removed!=1) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Could not isolate this image safely.");
        if(!remove) {
            if(!replacement || !count) { png=fz_new_buffer_from_image_as_png(ctx,state.image,fz_default_color_params); count=fz_buffer_storage(ctx,png,(unsigned char**)&replacement); }
            if(!pe_image(e,page,destination,replacement,count)) fz_throw(ctx,FZ_ERROR_GENERIC,"%s",e->error);
        }
    } fz_always(ctx) { fz_drop_image(ctx,state.image); fz_drop_buffer(ctx,png); fz_drop_stext_page(ctx,t); fz_drop_page(ctx,(fz_page*)p); } CATCH;
}
int pe_edit_link(PEEngine *e,int page,int index,PERect r,const char *uri,int remove) {
    CTX; TRY {
        pdf_obj *pageobj=pdf_lookup_page_obj(ctx,e->doc,page); pdf_obj *annots=pdf_dict_get(ctx,pageobj,PDF_NAME(Annots)); int n=0,found=-1;
        for(int i=0;i<pdf_array_len(ctx,annots);i++) if(pdf_name_eq(ctx,pdf_dict_get(ctx,pdf_array_get(ctx,annots,i),PDF_NAME(Subtype)),PDF_NAME(Link))) { if(n++==index) { found=i; break; } }
        if(found<0) fz_throw(ctx,FZ_ERROR_ARGUMENT,"Link no longer exists.");
        pdf_array_delete(ctx,annots,found);
        if(!remove && !pe_link(e,page,r,uri)) fz_throw(ctx,FZ_ERROR_GENERIC,"%s",e->error);
    } CATCH;
}

const char *pe_line_text(const PETextLine *l) { return l->text; }
const char *pe_line_font(const PETextLine *l) { return l->font; }
