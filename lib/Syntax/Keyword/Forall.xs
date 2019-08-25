/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2016-2019 -- leonerd@leonerd.org.uk
 *  (C) Ryan Voots, 2019
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef HAVE_DMD_HELPER
#  include "DMD_helper.h"
#endif

#define HAVE_PERL_VERSION(R, V, S) \
    (PERL_REVISION > (R) || (PERL_REVISION == (R) && (PERL_VERSION > (V) || (PERL_VERSION == (V) && (PERL_SUBVERSION >= (S))))))

#if HAVE_PERL_VERSION(5, 31, 3)
#  define HAVE_PARSE_SUBSIGNATURE
#elif HAVE_PERL_VERSION(5, 26, 0)
#  include "parse_subsignature.c.inc"
#  define HAVE_PARSE_SUBSIGNATURE
#endif

#if !HAVE_PERL_VERSION(5, 24, 0)
  /* On perls before 5.24 we have to do some extra work to save the itervar
   * from being thrown away */
#  define HAVE_ITERVAR
#endif

#ifndef OpSIBLING
#  define OpSIBLING(op)  (op->op_sibling)
#endif

#if !HAVE_PERL_VERSION(5, 22, 0)
#  include "block_start.c.inc"
#  include "block_end.c.inc"

#  define CvPADLIST_set(cv, padlist)  (CvPADLIST(cv) = padlist)
#endif

/* Currently no version of perl makes this visible, so we always want it. Maybe
 * one day in the future we can make it version-dependent
 */

static void panic(char *fmt, ...);

#ifndef NOT_REACHED
#  define NOT_REACHED STMT_START { panic("Unreachable\n"); } STMT_END
#endif
#include "docatch.c.inc"


#ifdef DEBUG
#  define TRACEPRINT S_traceprint
static void S_traceprint(char *fmt, ...)
{
  /* TODO: make conditional */
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
}
#else
#  define TRACEPRINT(...)
#endif

static void debug_sv_summary(const SV *sv)
{
  const char *type;

  switch(SvTYPE(sv)) {
    case SVt_NULL: type = "NULL"; break;
    case SVt_IV:   type = "IV";   break;
    case SVt_NV:   type = "NV";   break;
    case SVt_PV:   type = "PV";   break;
    case SVt_PVGV: type = "PVGV"; break;
    case SVt_PVAV: type = "PVAV"; break;
    default: {
      char buf[16];
      sprintf(buf, "(%d)", SvTYPE(sv));
      type = buf;
      break;
    }
  }

  if(SvROK(sv))
    type = "RV";

  fprintf(stderr, "SV{type=%s,refcnt=%d", type, SvREFCNT(sv));

  if(SvTEMP(sv))
    fprintf(stderr, ",TEMP");

  if(SvROK(sv))
    fprintf(stderr, ",ROK");
  else {
    if(SvIOK(sv))
      fprintf(stderr, ",IV=%" IVdf, SvIVX(sv));
    if(SvUOK(sv))
      fprintf(stderr, ",UV=%" UVuf, SvUVX(sv));
    if(SvPOK(sv)) {
      fprintf(stderr, ",PVX=\"%.10s\"", SvPVX((SV *)sv));
      if(SvCUR(sv) > 10)
        fprintf(stderr, "...");
    }
  }

  fprintf(stderr, "}");
}

static void debug_showstack(const char *name)
{
  SV **sp;

  fprintf(stderr, "%s:\n", name ? name : "Stack");

  PERL_CONTEXT *cx = CX_CUR();

  I32 floor = cx->blk_oldsp;
  I32 *mark = PL_markstack + cx->blk_oldmarksp + 1;

  fprintf(stderr, "  marks (TOPMARK=@%d):\n", TOPMARK - floor);
  for(; mark <= PL_markstack_ptr; mark++)
    fprintf(stderr,  "    @%d\n", *mark - floor);

  mark = PL_markstack + cx->blk_oldmarksp + 1;
  for(sp = PL_stack_base + floor + 1; sp <= PL_stack_sp; sp++) {
    fprintf(stderr, sp == PL_stack_sp ? "-> " : "   ");
    fprintf(stderr, "%p = ", *sp);
    debug_sv_summary(*sp);
    while(mark <= PL_markstack_ptr && PL_stack_base + *mark == sp)
      fprintf(stderr, " [*M]"), mark++;
    fprintf(stderr, "\n");
  }
}

static void vpanic(char *fmt, va_list args)
{
  fprintf(stderr, "Syntax::Keyword::Forall panic: ");
  vfprintf(stderr, fmt, args);
  raise(SIGABRT);
}

static void panic(char *fmt, ...)
{
  va_list args;
  va_start(args, fmt);
  vpanic(fmt, args);
}

/*
 * Lexer extensions
 */

#define lex_consume(s)  MY_lex_consume(aTHX_ s)
static int MY_lex_consume(pTHX_ char *s)
{
  /* I want strprefix() */
  size_t i;
  for(i = 0; s[i]; i++) {
    if(s[i] != PL_parser->bufptr[i])
      return 0;
  }

  lex_read_to(PL_parser->bufptr + i);
  return i;
}

#define sv_cat_c(sv, c)  MY_sv_cat_c(aTHX_ sv, c)
static void MY_sv_cat_c(pTHX_ SV *sv, U32 c)
{
  char ds[UTF8_MAXBYTES + 1], *d;
  d = (char *)uvchr_to_utf8((U8 *)ds, c);
  if (d - ds > 1) {
    sv_utf8_upgrade(sv);
  }
  sv_catpvn(sv, ds, d - ds);
}

#define lex_scan_ident()  MY_lex_scan_ident(aTHX)
static SV *MY_lex_scan_ident(pTHX)
{
  /* Inspired by
   *   https://metacpan.org/source/MAUKE/Function-Parameters-1.0705/Parameters.xs#L265
   */
  I32 c;
  bool at_start;
  SV *ret = newSVpvs("");
  if(lex_bufutf8())
    SvUTF8_on(ret);

  at_start = TRUE;

  c = lex_peek_unichar(0);

  while(c != -1) {
    if(at_start ? isIDFIRST_uni(c) : isALNUM_uni(c)) {
      at_start = FALSE;
      sv_cat_c(ret, lex_read_unichar(0));

      c = lex_peek_unichar(0);
    }
    else
      break;
  }

  if(SvCUR(ret))
    return ret;

  SvREFCNT_dec(ret);
  return NULL;
}

/*
 * Keyword plugins
 */

static int forall_keyword_plugin(pTHX_ OP **op_ptr)
{
  lex_read_space(0);

  /* TODO update comments here */
  /* At this point we want to parse the sub NAME BLOCK or sub BLOCK
   * We can't just call parse_fullstmt because that will do too much that we
   *   can't hook into. We'll have to go a longer way round.
   */

  /* TODO make this not need to be lexical */
  /* forall must be immediately followed by 'my' */
  if(!lex_consume("my"))
    croak("Expected forall to be followed by my");
  lex_read_space(0);

#ifdef HAVE_PARSE_SUBSIGNATURE
  OP *sigop = NULL;
  if(lex_peek_unichar(0) == '(') {
    lex_read_unichar(0);

    sigop = parse_subsignature(0);
    lex_read_space(0);

    if(PL_parser->error_count)
      return 0;

    if(lex_peek_unichar(0) != ')')
      croak("Expected ')'");
    lex_read_unichar(0);
    lex_read_space(0);
  } else {
    croak("Expected iterator variables after my");
  }
#else
  #error "Missing parse_subsignature in compilation"
#endif

  /* TODO parse list variables to iterate on */

  if(lex_peek_unichar(0) != '{')
    croak("Expected async sub %sto be followed by '{'", name ? "NAME " : "");

  I32 save_ix = block_start(TRUE);

  OP *body = parse_block(0);

  body = block_end(save_ix, body);

#ifdef HAVE_PARSE_SUBSIGNATURE
  if(sigop)
    body = op_append_list(OP_LINESEQ, sigop, body);
#else
   #error "Missing parse_subsignature in compilation"
#endif

  /* turn block into
   *    NEXTSTATE; PUSHMARK; eval { BLOCK }; LEAVEASYNC
   */

  OP *op = newSTATEOP(0, NULL, NULL);
  op = op_append_elem(OP_LINESEQ, op, newOP(OP_PUSHMARK, 0));

  OP *try;
  op = op_append_elem(OP_LINESEQ, op, try = newUNOP(OP_ENTERTRY, 0, body));
  op_contextualize(try, G_ARRAY);

  op = op_append_elem(OP_LINESEQ, op, newLEAVEASYNCOP(OPf_WANT_SCALAR));

  CV *cv = newATTRSUB(floor_ix,
    name ? newSVOP(OP_CONST, 0, SvREFCNT_inc(name)) : NULL,
    NULL,
    attrs,
    op);

  if(name) {
    *op_ptr = newOP(OP_NULL, 0);

    SvREFCNT_dec(name);
    return KEYWORD_PLUGIN_STMT;
  }
  else {
    *op_ptr = newUNOP(OP_REFGEN, 0,
      newSVOP(OP_ANONCODE, 0, (SV *)cv));

    return KEYWORD_PLUGIN_EXPR;
  }
}

static int (*next_keyword_plugin)(pTHX_ char *, STRLEN, OP **);

static int my_keyword_plugin(pTHX_ char *kw, STRLEN kwlen, OP **op_ptr)
{
  HV *hints = GvHV(PL_hintgv);

  if((PL_parser && PL_parser->error_count) ||
     !hints)
    return (*next_keyword_plugin)(aTHX_ kw, kwlen, op_ptr);

  if(kwlen == 6 && strEQ(kw, "forall") &&
      hv_fetchs(hints, "Syntax::Keyword::Forall", 0))
    return forall_keyword_plugin(aTHX_ op_ptr);

  return (*next_keyword_plugin)(aTHX_ kw, kwlen, op_ptr);
}

MODULE = Syntax::Keyword::Forall    PACKAGE = Syntax::Keyword::Forall

int
__cxstack_ix()
  CODE:
    RETVAL = cxstack_ix;
  OUTPUT:
    RETVAL

BOOT:
  next_keyword_plugin = PL_keyword_plugin;
  PL_keyword_plugin = &my_keyword_plugin;
#ifdef HAVE_DMD_HELPER
  DMD_SET_MAGIC_HELPER(&vtbl, dumpmagic);
#endif
