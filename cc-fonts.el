;;; cc-fonts.el --- font lock support for CC Mode

;; Copyright (C) 2002, 03 Free Software Foundation, Inc.

;; Authors:    2003- Alan Mackenzie
;;             2002- Martin Stjernholm
;; Maintainer: bug-cc-mode@gnu.org
;; Created:    07-Jan-2002
;; Version:    See cc-mode.el
;; Keywords:   c languages oop

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Some comments on the use of faces:
;;
;; o  `c-label-face-name' is either `font-lock-constant-face' (in
;;    Emacs), or `font-lock-reference-face'.
;;
;; o  `c-constant-face-name', `c-reference-face-name' and
;;    `c-doc-markup-face-name' are essentially set up like
;;    `c-label-face-name'.
;;
;; o  `c-preprocessor-face-name' is `font-lock-preprocessor-face' in
;;    XEmacs and - in lack of a closer equivalent -
;;    `font-lock-builtin-face' or `font-lock-reference-face' in Emacs.
;;
;; o  `c-doc-face-name' is `font-lock-doc-string-face' in XEmacs,
;;    `font-lock-doc-face' in Emacs 21 and later, or
;;    `font-lock-comment-face' in older Emacs (that since source
;;    documentation are actually comments in these languages, as opposed
;;    to elisp).
;;
;; TBD: We should probably provide real faces for the above uses and
;; instead initialize them from the standard faces.

;;; Code:

;; The faces that already have been put onto the text is tested in
;; various places to direct further fontifications.  For this to work,
;; the following assumptions regarding the faces must hold (apart from
;; the dependencies on the font locking order):
;;
;; o  `font-lock-comment-face' and the face in `c-doc-face-name' is
;;    not used in anything but comments.
;; o  If any face (e.g. `c-doc-markup-face-name') but those above is
;;    used in comments, it doesn't replace them.
;; o  `font-lock-string-face' is not used in anything but string
;;    literals (single or double quoted).
;; o  `font-lock-keyword-face' and the face in `c-label-face-name' are
;;    never overlaid with other faces.

(eval-when-compile
  (let ((load-path
	 (if (and (boundp 'byte-compile-dest-file)
		  (stringp byte-compile-dest-file))
	     (cons (file-name-directory byte-compile-dest-file) load-path)
	   load-path)))
    (load "cc-bytecomp" nil t)))

(cc-require 'cc-defs)
(cc-require-when-compile 'cc-langs)
(cc-require 'cc-vars)
(cc-require 'cc-engine)
(cc-require-when-compile 'cc-awk) ; Change from cc-require, 2003/6/18 to
;; prevent cc-awk being loaded when it's not needed.  There is now a (require
;; 'cc-awk) in (defun awk-mode ..).

;; Avoid repeated loading through the eval-after-load directive in
;; cc-mode.el.
(provide 'cc-fonts)

(cc-external-require 'font-lock)

(cc-bytecomp-defvar parse-sexp-lookup-properties) ; Emacs only.

;; Need to declare these local symbols during compilation since
;; they're referenced from lambdas in `byte-compile' calls that are
;; executed at compile time.  They don't need to have the proper
;; definitions, though, since the generated functions aren't called
;; during compilation.
(cc-bytecomp-defvar c-preprocessor-face-name)
(cc-bytecomp-defvar c-reference-face-name)
(cc-bytecomp-defun c-fontify-recorded-types-and-refs)
(cc-bytecomp-defun c-font-lock-declarators)
(cc-bytecomp-defun c-font-lock-objc-method)
(cc-bytecomp-defun c-font-lock-invalid-string)


;; Note that font-lock in XEmacs doesn't expand face names as
;; variables, so we have to use the (eval . FORM) in the font lock
;; matchers wherever we use these alias variables.

(defconst c-preprocessor-face-name
  (cond ((c-face-name-p 'font-lock-preprocessor-face)
	 ;; XEmacs has a font-lock-preprocessor-face.
	 'font-lock-preprocessor-face)
	((c-face-name-p 'font-lock-builtin-face)
	 ;; In Emacs font-lock-builtin-face has traditionally been
	 ;; used for preprocessor directives.
	 'font-lock-builtin-face)
	(t
	 'font-lock-reference-face)))

(cc-bytecomp-defvar font-lock-constant-face)

(defconst c-label-face-name
  (cond ((c-face-name-p 'font-lock-label-face)
	 ;; If it happens to occur in the future.  (Well, the more
	 ;; pragmatic reason is to get unique faces for the test
	 ;; suite.)
	 'font-lock-label-face)
	((and (c-face-name-p 'font-lock-constant-face)
	      (eq font-lock-constant-face 'font-lock-constant-face))
	 ;; Test both if font-lock-constant-face exists and that it's
	 ;; not an alias for something else.  This is important since
	 ;; we compare already set faces in various places.
	 'font-lock-constant-face)
	(t
	 'font-lock-reference-face)))

(defconst c-constant-face-name
  (if (and (c-face-name-p 'font-lock-constant-face)
	   (eq font-lock-constant-face 'font-lock-constant-face))
      ;; This doesn't exist in some earlier versions of XEmacs 21.
      'font-lock-constant-face
    c-label-face-name))

(defconst c-reference-face-name
  (if (and (c-face-name-p 'font-lock-reference-face)
	   (eq font-lock-reference-face 'font-lock-reference-face))
      ;; This is considered obsolete in Emacs, but it still maps well
      ;; to this use.  (Another reason to do this is to get unique
      ;; faces for the test suite.)
      'font-lock-reference-face
    c-label-face-name))

;; This should not mapped to a face that also is used to fontify things
;; that aren't comments or string literals.
(defconst c-doc-face-name
  (cond ((c-face-name-p 'font-lock-doc-string-face)
	 ;; XEmacs.
	 'font-lock-doc-string-face)
	((c-face-name-p 'font-lock-doc-face)
	 ;; Emacs 21 and later.
	 'font-lock-doc-face)
	(t
	 'font-lock-comment-face)))

(defconst c-doc-markup-face-name
  (if (c-face-name-p 'font-lock-doc-markup-face)
	 ;; If it happens to occur in the future.  (Well, the more
	 ;; pragmatic reason is to get unique faces for the test
	 ;; suite.)
	 'font-lock-doc-markup-face
    c-label-face-name))

(cc-bytecomp-defun face-inverse-video-p) ; Only in Emacs.
(cc-bytecomp-defun face-property-instance) ; Only in XEmacs.

(defun c-make-inverse-face (oldface newface)
  ;; Emacs and XEmacs have completely different face manipulation
  ;; routines. :P
  (copy-face oldface newface)
  (cond ((fboundp 'face-inverse-video-p)
	 ;; Emacs.  This only looks at the inverse flag in the current
	 ;; frame.  Other display configurations might be different,
	 ;; but it can only show if the same Emacs has frames on
	 ;; e.g. a color and a monochrome display simultaneously.
	 (unless (face-inverse-video-p oldface)
	   (invert-face newface)))
	((fboundp 'face-property-instance)
	 ;; XEmacs.  Same pitfall here.
	 (unless (face-property-instance oldface 'reverse)
	   (invert-face newface)))))

(eval-and-compile
  ;; We need the following functions during compilation since they're
  ;; called when the `c-lang-defconst' initializers are evaluated.
  ;; Define them at runtime too for the sake of derived modes.

  (defmacro c-put-font-lock-face (from to face)
    ;; Put a face on a region (overriding any existing face) in the way
    ;; font-lock would do it.  In XEmacs that means putting an
    ;; additional font-lock property, or else the font-lock package
    ;; won't recognize it as fontified and might override it
    ;; incorrectly.
    ;;
    ;; This function does a hidden buffer change.
    (if (fboundp 'font-lock-set-face)
	;; Note: This function has no docstring in XEmacs so it might be
	;; considered internal.
	`(font-lock-set-face ,from ,to ,face)
      `(put-text-property ,from ,to 'face ,face)))

  (defmacro c-remove-font-lock-face (from to)
    ;; This is the inverse of `c-put-font-lock-face'.
    ;;
    ;; This function does a hidden buffer change.
    (if (fboundp 'font-lock-remove-face)
	`(font-lock-remove-face ,from ,to)
      `(remove-text-properties ,from ,to '(face nil))))

  (defmacro c-put-font-lock-string-face (from to)
    ;; Put `font-lock-string-face' on a string.  The surrounding
    ;; quotes are included in Emacs but not in XEmacs.  The passed
    ;; region should include them.
    ;;
    ;; This function does a hidden buffer change.
    (if (featurep 'xemacs)
	`(c-put-font-lock-face (1+ ,from) (1- ,to) 'font-lock-string-face)
      `(c-put-font-lock-face ,from ,to 'font-lock-string-face)))

  (defmacro c-fontify-types-and-refs (varlist &rest body)
    ;; Like `let', but additionally activates `c-record-type-identifiers'
    ;; and `c-record-ref-identifiers', and fontifies the recorded ranges
    ;; accordingly on exit.
    ;;
    ;; This function does hidden buffer changes.
    `(let ((c-record-type-identifiers t)
	   c-record-ref-identifiers
	   ,@varlist)
       (prog1 (progn ,@body)
	 (c-fontify-recorded-types-and-refs))))
  (put 'c-fontify-types-and-refs 'lisp-indent-function 1)

  (defun c-skip-comments-and-strings (limit)
    ;; If the point is within a region fontified as a comment or
    ;; string literal skip to the end of it or to LIMIT, whichever
    ;; comes first, and return t.  Otherwise return nil.  The match
    ;; data is not clobbered.
    ;;
    ;; This function might do hidden buffer changes.
    (when (c-got-face-at (point) c-literal-faces)
      (while (progn
	       (goto-char (next-single-property-change
			   (point) 'face nil limit))
	       (and (< (point) limit)
		    (c-got-face-at (point) c-literal-faces))))
      t))

  (defun c-make-font-lock-search-function (regexp &rest highlights)
    ;; This function makes a byte compiled function that works much like
    ;; a matcher element in `font-lock-keywords'.  It cuts out a little
    ;; bit of the overhead compared to a real matcher.  The main reason
    ;; is however to pass the real search limit to the anchored
    ;; matcher(s), since most (if not all) font-lock implementations
    ;; arbitrarily limits anchored matchers to the same line, and also
    ;; to insulate against various other irritating differences between
    ;; the different (X)Emacs font-lock packages.
    ;;
    ;; REGEXP is the matcher, which must be a regexp.  Only matches
    ;; where the beginning is outside any comment or string literal are
    ;; significant.
    ;;
    ;; HIGHLIGHTS is a list of highlight specs, just like in
    ;; `font-lock-keywords', with these limitations: The face is always
    ;; overridden (no big disadvantage, since hits in comments etc are
    ;; filtered anyway), there is no "laxmatch", and an anchored matcher
    ;; is always a form which must do all the fontification directly.
    ;; `limit' is a variable bound to the real limit in the context of
    ;; the anchored matcher forms.
    ;;
    ;; This function does not do any hidden buffer changes, but the
    ;; generated functions will.  (They are however used in places
    ;; covered by the font-lock context.)

    ;; Note: Replace `byte-compile' with `eval' to debug the generated
    ;; lambda easier.
    (byte-compile
     `(lambda (limit)
	(let (-match-end-pos-
	      ;; The font-lock package in Emacs is known to clobber
	      ;; `parse-sexp-lookup-properties' (when it exists).
	      (parse-sexp-lookup-properties
	       (cc-eval-when-compile
		 (boundp 'parse-sexp-lookup-properties))))
	  (while (re-search-forward ,regexp limit t)
	    (setq -match-end-pos- (point))
	    (unless (progn
		      (goto-char (match-beginning 0))
		      (c-skip-comments-and-strings limit))
	      (goto-char -match-end-pos-)
	      ,@(mapcar
		 (lambda (highlight)
		   (if (integerp (car highlight))
		       (progn
			 (unless (nth 2 highlight)
			   (error
			    "The override flag must currently be set in %s"
			    highlight))
			 (when (nth 3 highlight)
			   (error
			    "The laxmatch flag may currently not be set in %s"
			    highlight))
			 `(save-match-data
			    (c-put-font-lock-face
			     (match-beginning ,(car highlight))
			     (match-end ,(car highlight))
			     ,(elt highlight 1))))
		     (when (nth 3 highlight)
		       (error "Match highlights currently not supported in %s"
			      highlight))
		     `(progn
			,(nth 1 highlight)
			(save-match-data ,(car highlight))
			,(nth 2 highlight))))
		 highlights))))
	nil)))

  (eval-after-load "edebug"
    '(progn
       (def-edebug-spec c-fontify-types-and-refs let*)
       ;; If there are literal quoted or backquoted highlight specs in
       ;; the call to `c-make-font-lock-search-function' then let's
       ;; instrument the forms in them.
       (def-edebug-spec c-make-font-lock-search-function
	 (form &rest &or ("quote" (&rest form)) ("`" (&rest form)) form)))))

(defun c-fontify-recorded-types-and-refs ()
  ;; Convert the ranges recorded on `c-record-type-identifiers' and
  ;; `c-record-ref-identifiers' to fontification.
  ;;
  ;; This function does hidden buffer changes.
  (let (elem)
    (while (consp c-record-type-identifiers)
      (setq elem (car c-record-type-identifiers)
	    c-record-type-identifiers (cdr c-record-type-identifiers))
      (c-put-font-lock-face (car elem) (cdr elem)
			    'font-lock-type-face))
    (while c-record-ref-identifiers
      (setq elem (car c-record-ref-identifiers)
	    c-record-ref-identifiers (cdr c-record-ref-identifiers))
      ;; Note that the reference face is a variable that is
      ;; dereferenced, since it's an alias in Emacs.
      (c-put-font-lock-face (car elem) (cdr elem)
			    c-reference-face-name))))

(c-lang-defconst c-cpp-matchers
  "Font lock matchers for preprocessor directives and purely lexical
stuff.  Used on level 1 and higher."

  ;; Note: `c-font-lock-declarations' assumes that no matcher here
  ;; sets `font-lock-type-face' in languages where
  ;; `c-recognize-<>-arglists' is set.

  t `(,@(when (c-lang-const c-opt-cpp-prefix)
	  (let* ((noncontinued-line-end "\\(\\=\\|\\(\\=\\|[^\\]\\)[\n\r]\\)")
		 (ncle-depth (regexp-opt-depth noncontinued-line-end))
		 (sws-depth (c-lang-const c-syntactic-ws-depth)))
	    `(;; The stuff after #error and #warning is a message, so
	      ;; fontify it as a string.
	      (,(concat noncontinued-line-end
			(c-lang-const c-opt-cpp-prefix)
			"\\(error\\|warning\\)\\>\\s *\\(.*\\)$")
	       ,(+ ncle-depth 2) font-lock-string-face)

	      ;; Fontify filenames in #include <...> as strings.
	      (,(concat noncontinued-line-end
			(c-lang-const c-opt-cpp-prefix)
			"\\(import\\|include\\)\\>"
			(c-lang-const c-syntactic-ws)
			"\\(<[^>\n\r]*>?\\)")
	       (,(+ ncle-depth sws-depth 2)
		font-lock-string-face)

	       ;; Use an anchored matcher to put paren syntax on the brackets.
	       (,(byte-compile
		  `(lambda (limit)
		     (let ((beg-pos
			    (match-beginning ,(+ ncle-depth sws-depth 2)))
			   (end-pos
			    (1- (match-end ,(+ ncle-depth sws-depth 2)))))
		       (if (eq (char-after end-pos) ?>)
			   (progn
			     (c-mark-<-as-paren beg-pos)
			     (c-mark->-as-paren end-pos))
			 (c-clear-char-property beg-pos 'syntax-table)))
		     nil))))

	      ;; #define.
	      (,(c-make-font-lock-search-function
		 (concat
		  noncontinued-line-end
		  (c-lang-const c-opt-cpp-prefix)
		  "define\\>"
		  (c-lang-const c-syntactic-ws)
		  "\\(" (c-lang-const c-symbol-key) "\\)" ; 1 + ncle + sws
		  (concat "\\("		; 2 + ncle + sws + c-sym-key
			  ;; Macro with arguments - a "function".
			  "\\(\(\\)"	; 3 + ncle + sws + c-sym-key
			  "\\|"
			  ;; Macro without arguments - a "variable".
			  "\\([^\(]\\|$\\)"
			  "\\)"))
		 `((if (match-beginning ,(+ 3 ncle-depth sws-depth
					    (c-lang-const c-symbol-key-depth)))
		       ;; "Function".  Fontify the name and the arguments.
		       (save-restriction
			 (c-put-font-lock-face
			  (match-beginning ,(+ 1 ncle-depth sws-depth))
			  (match-end ,(+ 1 ncle-depth sws-depth))
			  'font-lock-function-name-face)
			 (goto-char (match-end
				     ,(+ 3 ncle-depth sws-depth
					 (c-lang-const c-symbol-key-depth))))

			 (narrow-to-region (point-min) limit)
			 (while (and
				 (progn
				   (c-forward-syntactic-ws)
				   (looking-at c-symbol-key))
				 (progn
				   (c-put-font-lock-face
				    (match-beginning 0) (match-end 0)
				    'font-lock-variable-name-face)
				   (goto-char (match-end 0))
				   (c-forward-syntactic-ws)
				   (eq (char-after) ?,)))
			   (forward-char)))

		     ;; "Variable".
		     (c-put-font-lock-face
		      (match-beginning ,(+ 1 ncle-depth sws-depth))
		      (match-end ,(+ 1 ncle-depth sws-depth))
		      'font-lock-variable-name-face)))))

	      ;; Fontify cpp function names in preprocessor
	      ;; expressions in #if and #elif.
	      ,@(when (c-lang-const c-cpp-defined-fns)
		  `((,(c-make-font-lock-search-function
		       (concat noncontinued-line-end
			       (c-lang-const c-opt-cpp-prefix)
			       "\\(if\\|elif\\)\\>" ; 1 + ncle-depth
			       ;; Match the whole logical line to look
			       ;; for the functions in.
			       "\\(\\\\\\(.\\|[\n\r]\\)\\|[^\n\r]\\)*")
		       `((let ((limit (match-end 0)))
			   (while (re-search-forward
				   ,(concat "\\<\\("
					    (regexp-opt
					     (c-lang-const c-cpp-defined-fns)
					     nil)
					    "\\)\\>"
					    "\\s *\(?")
				   limit 'move)
			     (c-put-font-lock-face (match-beginning 1)
						   (match-end 1)
						   c-preprocessor-face-name)))
			 (goto-char (match-end ,(1+ ncle-depth))))))))

	      ;; Fontify the directive names.
	      (,(c-make-font-lock-search-function
		 (concat noncontinued-line-end
			 "\\("
			 (c-lang-const c-opt-cpp-prefix)
			 "[" (c-lang-const c-symbol-chars) "]+"
			 "\\)")
		 `(,(1+ ncle-depth) c-preprocessor-face-name t)))
	      )))

      ,@(when (c-major-mode-is 'pike-mode)
	  `((eval . (list "\\`#![^\n\r]*"
			  0 c-preprocessor-face-name))))

      ;; Make hard spaces visible through an inverted `font-lock-warning-face'.
      (eval . (list
	       "\240"
	       0 (progn
		   (unless (c-face-name-p 'c-nonbreakable-space-face)
		     (c-make-inverse-face 'font-lock-warning-face
					  'c-nonbreakable-space-face))
		   ''c-nonbreakable-space-face)))
      ))

(defun c-font-lock-invalid-string ()
  ;; Assuming the point is after the opening character of a string,
  ;; fontify that char with `font-lock-warning-face' if the string
  ;; decidedly isn't terminated properly.
  ;;
  ;; This function does hidden buffer changes.
  (let ((start (1- (point))))
    (save-excursion
      (and (eq (elt (parse-partial-sexp start (c-point 'eol)) 8) start)
	   (if (c-major-mode-is '(c-mode c++-mode objc-mode pike-mode))
	       ;; There's no \ before the newline.
	       (not (eq (char-before (point)) ?\\))
	     ;; Quoted newlines aren't supported.
	     t)
	   (if (c-major-mode-is 'pike-mode)
	       ;; There's no # before the string, so newlines
	       ;; aren't allowed.
	       (not (eq (char-before start) ?#))
	     t)
	   (c-put-font-lock-face start (1+ start) 'font-lock-warning-face)))))

(c-lang-defconst c-basic-matchers-before
  "Font lock matchers for basic keywords, labels, references and various
other easily recognizable things that should be fontified before generic
casts and declarations are fontified.  Used on level 2 and higher."

  ;; Note: `c-font-lock-declarations' assumes that no matcher here
  ;; sets `font-lock-type-face' in languages where
  ;; `c-recognize-<>-arglists' is set.

  t `(;; Put a warning face on the opener of unclosed strings that
      ;; can't span lines.  Later font
      ;; lock packages have a `font-lock-syntactic-face-function' for
      ;; this, but it doesn't give the control we want since any
      ;; fontification done inside the function will be
      ;; unconditionally overridden.
      ,(c-make-font-lock-search-function
	;; Match a char before the string starter to make
	;; `c-skip-comments-and-strings' work correctly.
	(concat ".\\(" c-string-limit-regexp "\\)")
	'((c-font-lock-invalid-string)))

      ;; Fontify keyword constants.
      ,@(when (c-lang-const c-constant-kwds)
	  (let ((re (c-make-keywords-re nil (c-lang-const c-constant-kwds))))
	    (if (c-major-mode-is 'pike-mode)
		;; No symbol is a keyword after "->" in Pike.
		`((eval . (list ,(concat "\\(\\=\\|\\(\\=\\|[^-]\\)[^>]\\)"
					 "\\<\\(" re "\\)\\>")
				3 c-constant-face-name)))
	      `((eval . (list ,(concat "\\<\\(" re "\\)\\>")
			      1 c-constant-face-name))))))

      ;; Fontify all keywords except the primitive types.
      ,(if (c-major-mode-is 'pike-mode)
	   ;; No symbol is a keyword after "->" in Pike.
	   `(,(concat "\\(\\=\\|\\(\\=\\|[^-]\\)[^>]\\)"
		      "\\<" (c-lang-const c-regular-keywords-regexp))
	     3 font-lock-keyword-face)
	 `(,(concat "\\<" (c-lang-const c-regular-keywords-regexp))
	   1 font-lock-keyword-face))

      ;; Fontify leading identifiers in fully qualified names like
      ;; "foo::bar" in languages that supports such things.
      ,@(when (c-lang-const c-opt-identifier-concat-key)
	  (if (c-major-mode-is 'java-mode)
	      ;; Java needs special treatment since "." is used both to
	      ;; qualify names and in normal indexing.  Here we look for
	      ;; capital characters at the beginning of an identifier to
	      ;; recognize the class.  "*" is also recognized to cover
	      ;; wildcard import declarations.  All preceding dot separated
	      ;; identifiers are taken as package names and therefore
	      ;; fontified as references.
	      `(,(c-make-font-lock-search-function
		  ;; Search for class identifiers preceded by ".".  The
		  ;; anchored matcher takes it from there.
		  (concat (c-lang-const c-opt-identifier-concat-key)
			  (c-lang-const c-simple-ws) "*"
			  (concat "\\("
				  "[" c-upper "][" (c-lang-const c-symbol-chars) "]*"
				  "\\|"
				  "\\*"
				  "\\)"))
		  `((let (id-end)
		      (goto-char (1+ (match-beginning 0)))
		      (while (and (eq (char-before) ?.)
				  (progn
				    (backward-char)
				    (c-backward-syntactic-ws)
				    (setq id-end (point))
				    (< (skip-chars-backward
					,(c-lang-const c-symbol-chars)) 0))
				  (not (get-text-property (point) 'face)))
			(c-put-font-lock-face (point) id-end c-reference-face-name)
			(c-backward-syntactic-ws)))
		    nil
		    (goto-char (match-end 0)))))

	    `((,(byte-compile
		 ;; Must use a function here since we match longer than
		 ;; we want to move before doing a new search.  This is
		 ;; not necessary for XEmacs since it restarts the
		 ;; search from the end of the first highlighted
		 ;; submatch (something that causes problems in other
		 ;; places).
		 `(lambda (limit)
		    (while (re-search-forward
			    ,(concat "\\(\\<" ; 1
				     "\\(" (c-lang-const c-symbol-key) "\\)" ; 2
				     (c-lang-const c-simple-ws) "*"
				     (c-lang-const c-opt-identifier-concat-key)
				     (c-lang-const c-simple-ws) "*"
				     "\\)"
				     "\\("
				     (c-lang-const c-opt-after-id-concat-key)
				     "\\)")
			    limit t)
		      (unless (progn
				(goto-char (match-beginning 0))
				(c-skip-comments-and-strings limit))
			(or (get-text-property (match-beginning 2) 'face)
			    (c-put-font-lock-face (match-beginning 2)
						  (match-end 2)
						  c-reference-face-name))
			(goto-char (match-end 1))))))))))

      ;; Fontify the special declarations in Objective-C.
      ,@(when (c-major-mode-is 'objc-mode)
	  `(;; Fontify class names in the beginning of message expressions.
	    ,(c-make-font-lock-search-function
	      "\\["
	      '((c-fontify-types-and-refs ()
		  (c-forward-syntactic-ws limit)
		  (let ((start (point)))
		    ;; In this case we accept both primitive and known types.
		    (when (eq (c-forward-type) 'known)
		      (goto-char start)
		      (let ((c-promote-possible-types t))
			(c-forward-type))))
		  (if (> (point) limit) (goto-char limit)))))

	    ;; The @interface/@implementation/@protocol directives.
	    ,(c-make-font-lock-search-function
	      (concat "\\<"
		      (regexp-opt
		       '("@interface" "@implementation" "@protocol")
		       t)
		      "\\>")
	      '((c-fontify-types-and-refs
		    (;; The font-lock package in Emacs is known to clobber
		     ;; `parse-sexp-lookup-properties' (when it exists).
		     (parse-sexp-lookup-properties
		      (cc-eval-when-compile
			(boundp 'parse-sexp-lookup-properties))))
		  (c-forward-objc-directive)
		  nil)
		(goto-char (match-beginning 0))))))
      ))

(defun c-font-lock-complex-decl-prepare (limit)
  ;; Called before any of the matchers in `c-complex-decl-matchers'.
  ;; Nil is always returned.
  ;;
  ;; This function does hidden buffer changes.

  ;;(message "c-font-lock-complex-decl-prepare %s %s" (point) limit)

  ;; Clear the list of found types if we start from the start of the
  ;; buffer, to make it easier to get rid of misspelled types and
  ;; variables that has gotten recognized as types in malformed code.
  (when (bobp)
    (c-clear-found-types))

  ;; Clear the c-type char properties in the region to recalculate
  ;; them properly. This is necessary e.g. to handle constructs that
  ;; might been required as declarations temporarily during editing.
  ;; The interesting properties are anyway those put on the closest
  ;; token before the region.
  (c-clear-char-properties (point) limit 'c-type)

  ;; Update `c-state-cache' to the beginning of the region.  This will
  ;; make `c-beginning-of-syntax' go faster when it's used later on,
  ;; and it's near the point most of the time.
  (c-parse-state)

  ;; Check if the fontified region starts inside a declarator list so
  ;; that `c-font-lock-declarators' should be called at the start.
  (let ((prop (save-excursion
		(c-backward-syntactic-ws)
		(unless (bobp)
		  (c-get-char-property (1- (point)) 'c-type)))))
    (when (memq prop '(c-decl-id-start c-decl-type-start))
      (c-forward-syntactic-ws limit)
      (c-font-lock-declarators limit t (eq prop 'c-decl-type-start))))

  nil)

(defun c-font-lock-<>-arglists (limit)
  ;; Fontify types and references in names containing angle bracket
  ;; arglists from the point to LIMIT.  Note that
  ;; `c-font-lock-declarations' already has handled many of them.  Nil
  ;; is always returned.
  ;;
  ;; This function might do hidden buffer changes.

  (let (;; The font-lock package in Emacs is known to clobber
	;; `parse-sexp-lookup-properties' (when it exists).
	(parse-sexp-lookup-properties
	 (cc-eval-when-compile
	   (boundp 'parse-sexp-lookup-properties)))
	(c-parse-and-markup-<>-arglists t)
	c-restricted-<>-arglists
	id-start id-end id-face pos kwd-sym)

    (while (and (< (point) limit)
		(re-search-forward c-opt-<>-arglist-start limit t))

      (setq id-start (match-beginning 1)
	    id-end (match-end 1)
	    pos (point))

      (goto-char id-start)
      (unless (c-skip-comments-and-strings limit)
	(setq kwd-sym nil
	      c-restricted-<>-arglists nil
	      id-face (get-text-property id-start 'face))

	(if (cond
	     ((eq id-face 'font-lock-type-face)
	      ;; The identifier got the type face so it has already been
	      ;; handled in `c-font-lock-declarations'.
	      nil)

	     ((eq id-face 'font-lock-keyword-face)
	      (when (looking-at c-opt-<>-sexp-key)
		;; There's a special keyword before the "<" that tells
		;; that it's an angle bracket arglist.
		(setq kwd-sym (c-keyword-sym (match-string 1)))))

	     (t
	      ;; There's a normal identifier before the "<".  If we're not in
	      ;; a declaration context then we set `c-restricted-<>-arglists'
	      ;; to avoid recognizing templates in function calls like "foo (a
	      ;; < b, c > d)".
	      (c-backward-syntactic-ws)
	      (when (and (memq (char-before) '(?\( ?,))
			 (not (eq (get-text-property (1- (point)) 'c-type)
				  'c-decl-arg-start)))
		(setq c-restricted-<>-arglists t))
	      t))

	    (progn
	      (goto-char (1- pos))
	      ;; Check for comment/string both at the identifier and
	      ;; at the "<".
	      (unless (c-skip-comments-and-strings limit)

		(c-fontify-types-and-refs ()
		  (when (c-forward-<>-arglist (c-keyword-member
					       kwd-sym 'c-<>-type-kwds))
		    (when (and c-opt-identifier-concat-key
			       (not (get-text-property id-start 'face)))
		      (c-forward-syntactic-ws)
		      (if (looking-at c-opt-identifier-concat-key)
			  (c-put-font-lock-face id-start id-end
						c-reference-face-name)
			(c-put-font-lock-face id-start id-end
					      'font-lock-type-face)))))

		(goto-char pos)))
	  (goto-char pos)))))
  nil)

(defun c-font-lock-declarators (limit list types)
  ;; Assuming the point is at the start of a declarator in a
  ;; declaration, fontify it.  If LIST is non-nil, fontify also all
  ;; following declarators in a comma separated list (e.g.  "foo" and
  ;; "bar" in "int foo = 17, bar;").  Stop at LIMIT.  If TYPES is
  ;; non-nil, fontify all identifiers as types.  Nil is always
  ;; returned.
  ;;
  ;; This function might do hidden buffer changes.

  ;;(message "c-font-lock-declarators from %s to %s" (point) limit)
  (c-fontify-types-and-refs
      ((pos (point)) next-pos id-start id-end
       paren-depth
       id-face got-init
       c-last-identifier-range
       (separator-prop (if types 'c-decl-type-start 'c-decl-id-start)))

    (while (and
	    pos
	    (< (point) limit)

	    (let (got-identifier)
	      (setq paren-depth 0)
	      ;; Skip over type decl prefix operators.  (Note similar
	      ;; code in `c-forward-decl-or-cast-1'.)
	      (while (and (looking-at c-type-decl-prefix-key)
			  (if (and (c-major-mode-is 'c++-mode)
				   (match-beginning 2))
			      ;; If the second submatch matches in C++ then
			      ;; we're looking at an identifier that's a
			      ;; prefix only if it specifies a member pointer.
			      (progn
				(setq id-start (point))
				(c-forward-name)
				(if (looking-at "\\(::\\)")
				    ;; We only check for a trailing "::" and
				    ;; let the "*" that should follow be
				    ;; matched in the next round.
				    t
				  ;; It turned out to be the real identifier,
				  ;; so flag that and stop.
				  (setq got-identifier t)
				  nil))
			    t))
		(if (eq (char-after) ?\()
		    (progn
		      (setq paren-depth (1+ paren-depth))
		      (forward-char))
		  (goto-char (match-end 1)))
		(c-forward-syntactic-ws))

	      ;; If we didn't pass the identifier above already, do it now.
	      (unless got-identifier
		(setq id-start (point))
		(c-forward-name))
	      (setq id-end (point))

	      (/= id-end pos))

	    ;; Skip out of the parens surrounding the identifier.
	    (or (= paren-depth 0)
		(c-safe (goto-char (scan-lists (point) 1 paren-depth))))

	    (<= (point) limit)

	    ;; Search syntactically to the end of the declarator (";",
	    ;; ",", a closen paren, eob etc) or to the beginning of an
	    ;; initializer or function prototype ("=" or "\\s\(").
	    ;; Note that the open paren will match array specs in
	    ;; square brackets, and we treat them as initializers too.
	    (c-syntactic-re-search-forward
	     "[;,]\\|\\s)\\|\\'\\|\\(=\\|\\s(\\)" limit t t))

      (setq next-pos (match-beginning 0)
	    id-face (if (eq (char-after next-pos) ?\()
			'font-lock-function-name-face
		      'font-lock-variable-name-face)
	    got-init (and (match-beginning 1)
			  (char-after (match-beginning 1))))

      (if types
	  ;; Register and fontify the identifer as a type.
	  (let ((c-promote-possible-types t))
	    (goto-char id-start)
	    (c-forward-type))
	;; Fontify the last symbol in the identifier if it isn't fontified
	;; already.  The check is necessary only in certain cases where this
	;; function is used "sloppily", e.g. in `c-simple-decl-matchers'.
	(when (and c-last-identifier-range
		   (not (get-text-property (car c-last-identifier-range)
					   'face)))
	  (c-put-font-lock-face (car c-last-identifier-range)
				(cdr c-last-identifier-range)
				id-face)))

      (goto-char next-pos)
      (setq pos nil)
      (when list
	;; Jump past any initializer or function prototype to see if
	;; there's a ',' to continue at.

	(cond ((eq id-face 'font-lock-function-name-face)
	       ;; Skip a parenthesized initializer (C++) or a function
	       ;; prototype.
	       (if (c-safe (c-forward-sexp 1) t)
		   (c-forward-syntactic-ws limit)
		 (goto-char limit)))

	      (got-init
	       ;; Skip an initializer expression.  If we're at a '='
	       ;; then accept a brace list directly after it to cope
	       ;; with array initializers.  Otherwise stop at braces
	       ;; to avoid going past full function and class blocks.
	       (and (if (and (eq got-init ?=)
			     (= (c-forward-token-2) 0)
			     (looking-at "{"))
			(c-safe (c-forward-sexp) t)
		      t)
		    ;; FIXME: Should look for c-decl-end markers here;
		    ;; we might go far into the following declarations
		    ;; in e.g. ObjC mode (see e.g. methods-4.m).
		    (c-syntactic-re-search-forward "[;,{]" limit 'move t)
		    (backward-char)))

	      (t (c-forward-syntactic-ws limit)))

	;; If a ',' is found we set pos to the next declarator and iterate.
	(when (and (< (point) limit) (looking-at ","))
	  (c-put-char-property (point) 'c-type separator-prop)
	  (forward-char)
	  (c-forward-syntactic-ws limit)
	  (setq pos (point))))))
  nil)

(defconst c-font-lock-maybe-decl-faces
  ;; List of faces that might be put at the start of a type when
  ;; `c-font-lock-declarations' runs.  This needs to be evaluated to
  ;; ensure that face name aliases in Emacs are resolved.
  (list nil
	font-lock-type-face
	c-reference-face-name
	font-lock-keyword-face))

(defun c-font-lock-declarations (limit)
  ;; Fontify all the declarations, casts and labels from the point to LIMIT.
  ;; Assumes that strings and comments have been fontified already.  Nil is
  ;; always returned.
  ;;
  ;; This function might do hidden buffer changes.

  ;;(message "c-font-lock-declarations search from %s to %s" (point) limit)

  (save-restriction
    (let (;; The position where `c-find-decl-spots' stopped.
	  start-pos
	  ;; 'decl if we're in an arglist containing declarations (but
	  ;; if `c-recognize-paren-inits' is set it might also be an
	  ;; initializer arglist), '<> if the arglist is of angle
	  ;; bracket type, 'arglist if it's some other arglist, or nil
	  ;; if not in an arglist at all.
	  context
	  ;; The position of the next token after the closing paren of
	  ;; the last detected cast.
	  last-cast-end
	  ;; The result from `c-forward-decl-or-cast-1'.
	  decl-or-cast
	  ;; The maximum of the end positions of all the checked type
	  ;; decl expressions in the successfully identified
	  ;; declarations.  The position might be either before or
	  ;; after the syntactic whitespace following the last token
	  ;; in the type decl expression.
	  (max-type-decl-end 0)
	  ;; Same as `max-type-decl-*', but used when we're before
	  ;; `token-pos'.
	  (max-type-decl-end-before-token 0)
	  ;; Set according to the context to direct the heuristics for
	  ;; recognizing C++ templates.
	  c-restricted-<>-arglists
	  ;; Turn on recording of identifier ranges in
	  ;; `c-forward-decl-or-cast-1' and `c-forward-label' for
	  ;; later fontification.
	  (c-record-type-identifiers t)
	  c-record-ref-identifiers
	  ;; Make `c-forward-type' calls mark up template arglists if
	  ;; it finds any.  That's necessary so that we later will
	  ;; stop inside them to fontify types there.
	  (c-parse-and-markup-<>-arglists t)
	  ;; The font-lock package in Emacs is known to clobber
	  ;; `parse-sexp-lookup-properties' (when it exists).
	  (parse-sexp-lookup-properties
	   (cc-eval-when-compile
	     (boundp 'parse-sexp-lookup-properties))))

      ;; Below we fontify a whole declaration even when it crosses the limit,
      ;; to avoid gaps when lazy-lock fontifies the file a screenful at a
      ;; time.  That is however annoying during editing, e.g. the following is
      ;; a common situation while the first line is being written:
      ;;
      ;;     my_variable
      ;;     some_other_variable = 0;
      ;;
      ;; font-lock will put the limit at the beginning of the second line
      ;; here, and if we go past it we'll fontify "my_variable" as a type and
      ;; "some_other_variable" as an identifier, and the latter will not
      ;; correct itself until the second line is changed.  To avoid that we
      ;; narrow to the limit if the region to fontify is a single line.
      (narrow-to-region
       (point-min)
       (if (<= limit (c-point 'bonl))
	   (save-excursion
	     ;; Narrow after any operator chars following the limit though,
	     ;; since those characters can be useful in recognizing a
	     ;; declaration (in particular the '{' that opens a function body
	     ;; after the header).
	     (goto-char limit)
	     (skip-chars-forward c-nonsymbol-chars)
	     (point))
	 limit))

      (c-find-decl-spots
       limit
       c-decl-start-re
       c-font-lock-maybe-decl-faces

       (lambda (match-pos inside-macro)
	 (setq start-pos (point))
	 (when
	  ;; The result of the form below is true when we don't recognize a
	  ;; declaration or cast.
	  (if (and (eq (get-text-property (point) 'face)
		       'font-lock-keyword-face)
		   (looking-at c-not-decl-init-keywords))
	      ;; Don't do anything more if we're looking at a keyword that
	      ;; can't start a declaration.
	      t

	    ;; Set `context'.  Look for "<" for the sake of C++-style template
	    ;; arglists.
	    (if (memq (char-before match-pos) '(?\( ?, ?\[ ?<))

		;; Find out the type of the arglist.
		(if (<= match-pos (point-min))
		    (setq context 'arglist)
		  (let ((type (c-get-char-property (1- match-pos) 'c-type)))
		    (cond ((eq type 'c-decl-arg-start)
			   ;; Got a cached hit in a declaration arglist.
			   (setq context 'decl))
			  ((or (eq type 'c-<>-arg-sep)
			       (eq (char-before match-pos) ?<))
			   ;; Inside an angle bracket arglist.
			   (setq context '<>))
			  (type
			   ;; Got a cached hit in some other type of arglist.
			   (setq context 'arglist))
			  ((if inside-macro
			       (< match-pos max-type-decl-end-before-token)
			     (< match-pos max-type-decl-end))
			   ;; The point is within the range of a previously
			   ;; encountered type decl expression, so the arglist
			   ;; is probably one that contains declarations.
			   ;; However, if `c-recognize-paren-inits' is set it
			   ;; might also be an initializer arglist.
			   (setq context 'decl)
			   ;; The result of this check is cached with a char
			   ;; property on the match token, so that we can look
			   ;; it up again when refontifying single lines in a
			   ;; multiline declaration.
			   (c-put-char-property (1- match-pos)
						'c-type 'c-decl-arg-start))
			  (t
			   (setq context 'arglist)))))

	      (setq context nil))

	    ;; If we're in a normal arglist context we don't want to
	    ;; recognize commas in nested angle bracket arglists since
	    ;; those commas could be part of our own arglist.
	    (setq c-restricted-<>-arglists (and c-recognize-<>-arglists
						(eq context 'arglist))

		  ;; Now analyze the construct.
		  decl-or-cast (c-forward-decl-or-cast-1
				match-pos context last-cast-end))

	    (if (not decl-or-cast)
		;; False alarm.  Return t to go on to the next check.
		t

	      (if (eq decl-or-cast 'cast)
		  ;; Save the position after the previous cast so we can feed
		  ;; it to `c-forward-decl-or-cast-1' in the next round.  That
		  ;; helps it discover cast chains like "(a) (b) c".
		  (setq last-cast-end (point))

		;; Set `max-type-decl-end' or `max-type-decl-end-before-token'
		;; under the assumption that we're after the first type decl
		;; expression in the declaration now.  That's not really true;
		;; we could also be after a parenthesized initializer
		;; expression in C++, but this is only used as a last resort
		;; to slant ambiguous expression/declarations, and overall
		;; it's worth the risk to occasionally fontify an expression
		;; as a declaration in an initializer expression compared to
		;; getting ambiguous things in normal function prototypes
		;; fontified as expressions.
		(if inside-macro
		    (when (> (point) max-type-decl-end-before-token)
		      (setq max-type-decl-end-before-token (point)))
		  (when (> (point) max-type-decl-end)
		    (setq max-type-decl-end (point))))

		;; Back up to the type to fontify the declarator(s).
		(goto-char (car decl-or-cast))

		(let ((decl-list
		       (if context
			   ;; Should normally not fontify a list of
			   ;; declarators inside an arglist, but the first
			   ;; argument in the ';' separated list of a "for"
			   ;; statement is an exception.
			   (when (eq (char-before match-pos) ?\()
			     (save-excursion
			       (goto-char (1- match-pos))
			       (c-backward-syntactic-ws)
			       (and (c-simple-skip-symbol-backward)
				    (looking-at c-paren-stmt-key))))
			 t)))

		  ;; Fix the `c-decl-id-start' or `c-decl-type-start' property
		  ;; before the first declarator if it's a list.
		  ;; `c-font-lock-declarators' handles the rest.
		  (when decl-list
		    (save-excursion
		      (c-backward-syntactic-ws)
		      (unless (bobp)
			(c-put-char-property (1- (point)) 'c-type
					     (if (cdr decl-or-cast)
						 'c-decl-type-start
					       'c-decl-id-start)))))

		  (c-font-lock-declarators
		   (point-max) decl-list (cdr decl-or-cast))))

	      ;; A cast or declaration has been successfully identified, so do
	      ;; all the fontification of types and refs that's been recorded.
	      (c-fontify-recorded-types-and-refs)
	      nil))

	  ;; It was a false alarm.  Check if we're in a label instead.
	  (goto-char start-pos)
	  (when (c-forward-label t match-pos nil)
	    ;; Can't use `c-fontify-types-and-refs' here since we
	    ;; should use the label face.
	    (let (elem)
	      (while c-record-ref-identifiers
		(setq elem (car c-record-ref-identifiers)
		      c-record-ref-identifiers (cdr c-record-ref-identifiers))
		(c-put-font-lock-face (car elem) (cdr elem)
				      c-label-face-name)))
	    ;; `c-forward-label' probably has added a `c-decl-end'
	    ;; marker, so return t to `c-find-decl-spots' to signal
	    ;; that.
	    t))))

      nil)))

(c-lang-defconst c-simple-decl-matchers
  "Simple font lock matchers for types and declarations.  These are used
on level 2 only and so aren't combined with `c-complex-decl-matchers'."

  t `(;; Objective-C methods.
      ,@(when (c-major-mode-is 'objc-mode)
	  `((,(c-lang-const c-opt-method-key)
	     (,(byte-compile
		(lambda (limit)
		  (let (;; The font-lock package in Emacs is known to clobber
			;; `parse-sexp-lookup-properties' (when it exists).
			(parse-sexp-lookup-properties
			 (cc-eval-when-compile
			   (boundp 'parse-sexp-lookup-properties))))
		    (save-restriction
		      (narrow-to-region (point-min) limit)
		      (c-font-lock-objc-method)))
		  nil))
	      (goto-char (match-end 1))))))

      ;; Fontify all type names and the identifiers in the
      ;; declarations they might start.  Use eval here since
      ;; `c-known-type-key' gets its value from
      ;; `*-font-lock-extra-types' on mode init.
      (eval . (list ,(c-make-font-lock-search-function
		      'c-known-type-key
		      '(1 'font-lock-type-face t)
		      '((c-font-lock-declarators limit t nil)
			(save-match-data
			  (goto-char (match-end 1))
			  (c-forward-syntactic-ws))
			(goto-char (match-end 1))))))

      ;; Fontify types preceded by `c-type-prefix-kwds' and the
      ;; identifiers in the declarations they might start.
      ,@(when (c-lang-const c-type-prefix-kwds)
	  (let* ((prefix-re (c-make-keywords-re nil
			      (c-lang-const c-type-prefix-kwds)))
		 (type-match (+ 2
				(regexp-opt-depth prefix-re)
				(c-lang-const c-simple-ws-depth))))
	    `((,(c-make-font-lock-search-function
		 (concat "\\<\\(" prefix-re "\\)" ; 1
			 (c-lang-const c-simple-ws) "+"
			 (concat "\\("	; 2 + prefix-re + c-simple-ws
				 (c-lang-const c-symbol-key)
				 "\\)"))
		 `(,type-match
		   'font-lock-type-face t)
		 `((c-font-lock-declarators limit t nil)
		   (save-match-data
		     (goto-char (match-end ,type-match))
		     (c-forward-syntactic-ws))
		   (goto-char (match-end ,type-match))))))))

      ;; Fontify special declarations that lacks a type.
      ,@(when (c-lang-const c-typeless-decl-kwds)
	  `((,(c-make-font-lock-search-function
	       (concat "\\<\\("
		       (regexp-opt (c-lang-const c-typeless-decl-kwds))
		       "\\)\\>")
	       '((c-font-lock-declarators limit t nil)
		 (save-match-data
		   (goto-char (match-end 1))
		   (c-forward-syntactic-ws))
		 (goto-char (match-end 1)))))))

      ;; Fontify generic colon labels in languages that support them.
      ,@(when (c-lang-const c-recognize-colon-labels)
	  `(c-font-lock-labels))))

(c-lang-defconst c-complex-decl-matchers
  "Complex font lock matchers for types and declarations.  Used on level
3 and higher."

  t `(;; Initialize some things before the search functions below.
      c-font-lock-complex-decl-prepare

      ,@(if (c-major-mode-is 'objc-mode)
	    ;; Fontify method declarations in Objective-C, but first
	    ;; we have to put the `c-decl-end' `c-type' property on
	    ;; all the @-style directives that haven't been handled in
	    ;; `c-basic-matchers-before'.
	    `(,(c-make-font-lock-search-function
		(c-make-keywords-re t
		  ;; Exclude "@class" since that directive ends with a
		  ;; semicolon anyway.
		  (delete "@class"
			  (append (c-lang-const c-protection-kwds)
				  (c-lang-const c-other-decl-kwds)
				  nil)))
		'((c-put-char-property (1- (match-end 1))
				       'c-type 'c-decl-end)))
	      c-font-lock-objc-methods))

      ;; Fontify all declarations, casts and normal labels.
      c-font-lock-declarations

      ;; Fontify angle bracket arglists like templates in C++.
      ,@(when (c-lang-const c-recognize-<>-arglists)
	  `(c-font-lock-<>-arglists))

      ;; The first two rules here mostly find occurences that
      ;; `c-font-lock-declarations' has found already, but not
      ;; declarations containing blocks in the type (see note below).
      ;; It's also useful to fontify these everywhere to show e.g. when
      ;; a type keyword is accidentally used as an identifier.

      ;; Fontify basic types.
      ,(let ((re (c-make-keywords-re nil
		   (c-lang-const c-primitive-type-kwds))))
	 (if (c-major-mode-is 'pike-mode)
	     ;; No symbol is a keyword after "->" in Pike.
	     `(,(concat "\\(\\=\\|\\(\\=\\|[^-]\\)[^>]\\)"
			"\\<\\(" re "\\)\\>")
	       3 font-lock-type-face)
	   `(,(concat "\\<\\(" re "\\)\\>")
	     1 'font-lock-type-face)))

      ;; Fontify types preceded by `c-type-prefix-kwds'.
      ,@(when (c-lang-const c-type-prefix-kwds)
	  `((,(byte-compile
	       `(lambda (limit)
		  (c-fontify-types-and-refs
		      ((c-promote-possible-types t)
		       ;; The font-lock package in Emacs is known to clobber
		       ;; `parse-sexp-lookup-properties' (when it exists).
		       (parse-sexp-lookup-properties
			(cc-eval-when-compile
			  (boundp 'parse-sexp-lookup-properties))))
		    (save-restriction
		      ;; Narrow to avoid going past the limit in
		      ;; `c-forward-type'.
		      (narrow-to-region (point) limit)
		      (while (re-search-forward
			      ,(concat "\\<\\("
				       (c-make-keywords-re nil
					 (c-lang-const c-type-prefix-kwds))
				       "\\)\\>")
			      limit t)
			(unless (c-skip-comments-and-strings limit)
			  (c-forward-syntactic-ws)
			  ;; Handle prefix declaration specifiers.
			  (when (looking-at c-prefix-spec-kwds-re)
			    (c-forward-keyword-clause 1))
			  ,(if (c-major-mode-is 'c++-mode)
			       `(when (and (c-forward-type)
					   (eq (char-after) ?=))
				  ;; In C++ we additionally check for a "class
				  ;; X = Y" construct which is used in
				  ;; templates, to fontify Y as a type.
				  (forward-char)
				  (c-forward-syntactic-ws)
				  (c-forward-type))
			     `(c-forward-type))
			  )))))))))

      ;; Fontify symbols after closing braces as declaration
      ;; identifiers under the assumption that they are part of
      ;; declarations like "class Foo { ... } foo;".  It's too
      ;; expensive to check this accurately by skipping past the
      ;; brace block, so we use the heuristic that it's such a
      ;; declaration if the first identifier is on the same line as
      ;; the closing brace.  `c-font-lock-declarations' will later
      ;; override it if it turns out to be an new declaration, but
      ;; it will be wrong if it's an expression (see the test
      ;; decls-8.cc).
      ,@(when (c-lang-const c-opt-block-decls-with-vars-key)
	  `((,(c-make-font-lock-search-function
	       (concat "}"
		       (c-lang-const c-single-line-syntactic-ws)
		       "\\("		; 1 + c-single-line-syntactic-ws-depth
		       (c-lang-const c-type-decl-prefix-key)
		       "\\|"
		       (c-lang-const c-symbol-key)
		       "\\)")
	       `((c-font-lock-declarators limit t nil)
		 (progn
		   (c-put-char-property (match-beginning 0) 'c-type
					'c-decl-id-start)
		   (goto-char (match-beginning
			       ,(1+ (c-lang-const
				     c-single-line-syntactic-ws-depth)))))
		 (goto-char (match-end 0)))))))

      ;; Fontify the type in C++ "new" expressions.
      ,@(when (c-major-mode-is 'c++-mode)
	  `(("\\<new\\>"
	     (c-font-lock-c++-new))))
      ))

(defun c-font-lock-labels (limit)
  ;; Fontify all statement labels from the point to LIMIT.  Assumes
  ;; that strings and comments have been fontified already.  Nil is
  ;; always returned.
  ;;
  ;; Note: This function is only used on decoration level 2; this is
  ;; taken care of directly by the gargantuan
  ;; `c-font-lock-declarations' on higher levels.
  ;;
  ;; This function might do hidden buffer changes.

  (let (continue-pos id-start
	;; The font-lock package in Emacs is known to clobber
	;; `parse-sexp-lookup-properties' (when it exists).
	(parse-sexp-lookup-properties
	 (cc-eval-when-compile
	   (boundp 'parse-sexp-lookup-properties))))

    (while (re-search-forward ":[^:]" limit t)
      (setq continue-pos (point))
      (goto-char (match-beginning 0))
      (unless (c-skip-comments-and-strings limit)

	(c-backward-syntactic-ws)
	(and (setq id-start (c-on-identifier))

	     (not (get-text-property id-start 'face))

	     (progn
	       (goto-char id-start)
	       (c-backward-syntactic-ws)
	       (or
		;; Check for a char that precedes a statement.
		(memq (char-before) '(?\} ?\{ ?\;))
		;; Check for a preceding label.  We exploit the font
		;; locking made earlier by this function.
		(and (eq (char-before) ?:)
		     (progn
		       (backward-char)
		       (c-backward-syntactic-ws)
		       (not (bobp)))
		     (eq (get-text-property (1- (point)) 'face)
			 c-label-face-name))
		;; Check for a keyword that precedes a statement.
		(c-after-conditional)))

	     (progn
	       ;; Got a label.
	       (goto-char id-start)
	       (looking-at c-symbol-key)
	       (c-put-font-lock-face (match-beginning 0) (match-end 0)
				     c-label-face-name)))

	(goto-char continue-pos))))
  nil)

(c-lang-defconst c-basic-matchers-after
  "Font lock matchers for various things that should be fontified after
generic casts and declarations are fontified.  Used on level 2 and
higher."

  t `(;; Fontify the identifiers inside enum lists.  (The enum type
      ;; name is handled by `c-simple-decl-matchers' or
      ;; `c-complex-decl-matchers' below.
      ,@(when (c-lang-const c-brace-id-list-kwds)
	  `((,(c-make-font-lock-search-function
	       (concat
		"\\<\\("
		(c-make-keywords-re nil (c-lang-const c-brace-id-list-kwds))
		"\\)\\>"
		;; Disallow various common punctuation chars that can't come
		;; before the '{' of the enum list, to avoid searching too far.
		"[^\]\[{}();,/#=]*"
		"{")
	       '((c-font-lock-declarators limit t nil)
		 (save-match-data
		   (goto-char (match-end 0))
		   (c-put-char-property (1- (point)) 'c-type
					'c-decl-id-start)
		   (c-forward-syntactic-ws))
		 (goto-char (match-end 0)))))))

	;; Fontify labels after goto etc.
	,@(when (c-lang-const c-before-label-kwds)
	  `(;; (Got three different interpretation levels here,
	    ;; which makes it a bit complicated: 1) The backquote
	    ;; stuff is expanded when compiled or loaded, 2) the
	    ;; eval form is evaluated at font-lock setup (to
	    ;; substitute c-label-face-name correctly), and 3) the
	    ;; resulting structure is interpreted during
	    ;; fontification.)
	    (eval
	     . ,(let* ((c-before-label-re
			(c-make-keywords-re nil
			  (c-lang-const c-before-label-kwds))))
		  `(list
		    ,(concat "\\<\\(" c-before-label-re "\\)\\>"
			     "\\s *"
			     "\\("	; identifier-offset
			     (c-lang-const c-symbol-key)
			     "\\)")
		    (list ,(+ (regexp-opt-depth c-before-label-re) 2)
			  c-label-face-name nil t))))))

      ;; Fontify the clauses after various keywords.
      ,@(when (or (c-lang-const c-type-list-kwds)
		  (c-lang-const c-ref-list-kwds)
		  (c-lang-const c-colon-type-list-kwds)
		  (c-lang-const c-paren-type-kwds))
	  `((,(c-make-font-lock-search-function
	       (concat "\\<\\("
		       (c-make-keywords-re nil
			 (append (c-lang-const c-type-list-kwds)
				 (c-lang-const c-ref-list-kwds)
				 (c-lang-const c-colon-type-list-kwds)
				 (c-lang-const c-paren-type-kwds)))
		       "\\)\\>")
	       '((c-fontify-types-and-refs ((c-promote-possible-types t))
		   (c-forward-keyword-clause 1)
		   (if (> (point) limit) (goto-char limit))))))))
      ))

(c-lang-defconst c-matchers-1
  t (c-lang-const c-cpp-matchers))

(c-lang-defconst c-matchers-2
  t (append (c-lang-const c-matchers-1)
	    (c-lang-const c-basic-matchers-before)
	    (c-lang-const c-simple-decl-matchers)
	    (c-lang-const c-basic-matchers-after)))

(c-lang-defconst c-matchers-3
  t (append (c-lang-const c-matchers-1)
	    (c-lang-const c-basic-matchers-before)
	    (c-lang-const c-complex-decl-matchers)
	    (c-lang-const c-basic-matchers-after)))

(defun c-compose-keywords-list (base-list)
  ;; Incorporate the font lock keyword lists according to
  ;; `c-doc-comment-style' on the given keyword list and return it.
  ;; This is used in the function bindings of the
  ;; `*-font-lock-keywords-*' symbols since we have to build the list
  ;; when font-lock is initialized.

  (unless (memq c-doc-face-name c-literal-faces)
    (setq c-literal-faces (cons c-doc-face-name c-literal-faces)))

  (let* ((doc-keywords
	  (if (consp (car-safe c-doc-comment-style))
	      (cdr-safe (or (assq c-buffer-is-cc-mode c-doc-comment-style)
			    (assq 'other c-doc-comment-style)))
	    c-doc-comment-style))
	 (list (nconc (apply 'nconc
			     (mapcar
			      (lambda (doc-style)
				(let ((sym (intern
					    (concat (symbol-name doc-style)
						    "-font-lock-keywords"))))
				  (cond ((fboundp sym)
					 (funcall sym))
					((boundp sym)
					 (append (eval sym) nil)))))
			      (if (listp doc-keywords)
				  doc-keywords
				(list doc-keywords))))
		      base-list)))

    ;; Kludge: If `c-font-lock-complex-decl-prepare' is on the list we
    ;; move it first since the doc comment font lockers might add
    ;; `c-type' text properties, so they have to be cleared before that.
    (when (memq 'c-font-lock-complex-decl-prepare list)
      (setq list (cons 'c-font-lock-complex-decl-prepare
		       (delq 'c-font-lock-complex-decl-prepare
			     (append list nil)))))

    list))

(defun c-override-default-keywords (def-var)
  ;; This is used to override the value on a `*-font-lock-keywords'
  ;; variable only if it's nil or has the same value as one of the
  ;; `*-font-lock-keywords-*' variables.  Older font-lock packages
  ;; define a default value for `*-font-lock-keywords' which we want
  ;; to override, but we should otoh avoid clobbering a user setting.
  ;; This heuristic for that isn't perfect, but I can't think of any
  ;; better. /mast
  (when (and (boundp def-var)
	     (memq (symbol-value def-var)
		   (cons nil
			 (mapcar
			  (lambda (suffix)
			    (let ((sym (intern (concat (symbol-name def-var)
						       suffix))))
			      (and (boundp sym) (symbol-value sym))))
			  '("-1" "-2" "-3")))))
    ;; The overriding is done by unbinding the variable so that the normal
    ;; defvar will install its default value later on.
    (makunbound def-var)))


;;; C.

(c-override-default-keywords 'c-font-lock-keywords)

(defconst c-font-lock-keywords-1 (c-lang-const c-matchers-1 c)
  "Minimal font locking for C mode.
Fontifies only preprocessor directives (in addition to the syntactic
fontification of strings and comments).")

(defconst c-font-lock-keywords-2 (c-lang-const c-matchers-2 c)
  "Fast normal font locking for C mode.
In addition to `c-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `c-font-lock-extra-types', and the doc comment
styles specified by `c-doc-comment-style'.")

(defconst c-font-lock-keywords-3 (c-lang-const c-matchers-3 c)
  "Accurate normal font locking for C mode.
Like `c-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `c-font-lock-extra-types'.")

(defvar c-font-lock-keywords c-font-lock-keywords-3
  "Default expressions to highlight in C mode.")

(defun c-font-lock-keywords-2 ()
  (c-compose-keywords-list c-font-lock-keywords-2))
(defun c-font-lock-keywords-3 ()
  (c-compose-keywords-list c-font-lock-keywords-3))
(defun c-font-lock-keywords ()
  (c-compose-keywords-list c-font-lock-keywords))


;;; C++.

(defun c-font-lock-c++-new (limit)
  ;; Assuming point is after a "new" word, check that it isn't inside
  ;; a string or comment, and if so try to fontify the type in the
  ;; allocation expression.  Nil is always returned.
  ;;
  ;; As usual, C++ takes the prize in coming up with a hard to parse
  ;; syntax. :P
  ;;
  ;; This function might do hidden buffer changes.

  (unless (c-skip-comments-and-strings limit)
    (save-excursion
      (catch 'false-alarm
	;; A "new" keyword is followed by one to three expressions, where
	;; the type is the middle one, and the only required part.
	(let (expr1-pos expr2-pos
	      ;; Enable recording of identifier ranges in `c-forward-type'
	      ;; etc for later fontification.  Not using
	      ;; `c-fontify-types-and-refs' here since the ranges should
	      ;; be fontified selectively only when an allocation
	      ;; expression is successfully recognized.
	      (c-record-type-identifiers t)
	      c-record-ref-identifiers
	      ;; The font-lock package in Emacs is known to clobber
	      ;; `parse-sexp-lookup-properties' (when it exists).
	      (parse-sexp-lookup-properties
	       (cc-eval-when-compile
		 (boundp 'parse-sexp-lookup-properties))))
	  (c-forward-syntactic-ws)

	  ;; The first placement arglist is always parenthesized, if it
	  ;; exists.
	  (when (eq (char-after) ?\()
	    (setq expr1-pos (1+ (point)))
	    (condition-case nil
		(c-forward-sexp)
	      (scan-error (throw 'false-alarm t)))
	    (c-forward-syntactic-ws))

	  ;; The second expression is either a type followed by some "*" or
	  ;; "[...]" or similar, or a parenthesized type followed by a full
	  ;; identifierless declarator.
	  (setq expr2-pos (1+ (point)))
	  (cond ((eq (char-after) ?\())
		((let ((c-promote-possible-types t))
		   (c-forward-type)))
		(t (setq expr2-pos nil)))

	  (when expr1-pos
	    (cond
	     ((not expr2-pos)
	      ;; No second expression, so the first has to be a
	      ;; parenthesized type.
	      (goto-char expr1-pos)
	      (let ((c-promote-possible-types t))
		(c-forward-type)))

	     ((eq (char-before expr2-pos) ?\()
	      ;; Got two parenthesized expressions, so we have to look
	      ;; closer at them to decide which is the type.  No need to
	      ;; handle `c-record-ref-identifiers' since all references
	      ;; has already been handled by other fontification rules.
	      (let (expr1-res expr2-res)

		(goto-char expr1-pos)
		(when (setq expr1-res (c-forward-type))
		  (unless (looking-at
			   (cc-eval-when-compile
			     (concat (c-lang-const c-symbol-start c++)
				     "\\|[*:\)\[]")))
		    ;; There's something after the would-be type that
		    ;; can't be there, so this is a placement arglist.
		    (setq expr1-res nil)))

		(goto-char expr2-pos)
		(when (setq expr2-res (c-forward-type))
		  (unless (looking-at
			   (cc-eval-when-compile
			     (concat (c-lang-const c-symbol-start c++)
				     "\\|[*:\)\[]")))
		    ;; There's something after the would-be type that can't
		    ;; be there, so this is an initialization expression.
		    (setq expr2-res nil))
		  (when (and (c-go-up-list-forward)
			     (progn (c-forward-syntactic-ws)
				    (eq (char-after) ?\()))
		    ;; If there's a third initialization expression
		    ;; then the second one is the type, so demote the
		    ;; first match.
		    (setq expr1-res nil)))

		;; We fontify the most likely type, with a preference for
		;; the first argument since a placement arglist is more
		;; unusual than an initializer.
		(cond ((memq expr1-res '(t known prefix)))
		      ((memq expr2-res '(t known prefix)))
		      ((eq expr1-res 'found)
		       (let ((c-promote-possible-types t))
			 (goto-char expr1-pos)
			 (c-forward-type)))
		      ((eq expr2-res 'found)
		       (let ((c-promote-possible-types t))
			 (goto-char expr2-pos)
			 (c-forward-type)))
		      ((and (eq expr1-res 'maybe) (not expr2-res))
		       (let ((c-promote-possible-types t))
			 (goto-char expr1-pos)
			 (c-forward-type)))
		      ((and (not expr1-res) (eq expr2-res 'maybe))
		       (let ((c-promote-possible-types t))
			 (goto-char expr2-pos)
			 (c-forward-type)))
		      ;; If both type matches are 'maybe then we're
		      ;; too uncertain to promote either of them.
		      )))))

	  ;; Fontify the type that now is recorded in
	  ;; `c-record-type-identifiers', if any.
	  (c-fontify-recorded-types-and-refs)))))
  nil)

(c-override-default-keywords 'c++-font-lock-keywords)

(defconst c++-font-lock-keywords-1 (c-lang-const c-matchers-1 c++)
  "Minimal font locking for C++ mode.
Fontifies only preprocessor directives (in addition to the syntactic
fontification of strings and comments).")

(defconst c++-font-lock-keywords-2 (c-lang-const c-matchers-2 c++)
  "Fast normal font locking for C++ mode.
In addition to `c++-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `c++-font-lock-extra-types', and the doc comment
styles specified by `c-doc-comment-style'.")

(defconst c++-font-lock-keywords-3 (c-lang-const c-matchers-3 c++)
  "Accurate normal font locking for C++ mode.
Like `c++-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `c++-font-lock-extra-types'.")

(defvar c++-font-lock-keywords c++-font-lock-keywords-3
  "Default expressions to highlight in C++ mode.")

(defun c++-font-lock-keywords-2 ()
  (c-compose-keywords-list c++-font-lock-keywords-2))
(defun c++-font-lock-keywords-3 ()
  (c-compose-keywords-list c++-font-lock-keywords-3))
(defun c++-font-lock-keywords ()
  (c-compose-keywords-list c++-font-lock-keywords))


;;; Objective-C.

(defun c-font-lock-objc-method ()
  ;; Assuming the point is after the + or - that starts an Objective-C
  ;; method declaration, fontify it.  This must be done before normal
  ;; casts, declarations and labels are fontified since they will get
  ;; false matches in these things.
  ;;
  ;; This function might do hidden buffer changes.

  (c-fontify-types-and-refs
      ((first t)
       (c-promote-possible-types t))

    (while (and
	    (progn
	      (c-forward-syntactic-ws)

	      ;; An optional method type.
	      (if (eq (char-after) ?\()
		  (progn
		    (forward-char)
		    (c-forward-syntactic-ws)
		    (c-forward-type)
		    (prog1 (c-go-up-list-forward)
		      (c-forward-syntactic-ws)))
		t))

	    ;; The name.  The first time it's the first part of
	    ;; the function name, the rest of the time it's an
	    ;; argument name.
	    (looking-at c-symbol-key)
	    (progn
	      (goto-char (match-end 0))
	      (c-put-font-lock-face (match-beginning 0)
				    (point)
				    (if first
					'font-lock-function-name-face
				      'font-lock-variable-name-face))
	      (c-forward-syntactic-ws)

	      ;; Another optional part of the function name.
	      (when (looking-at c-symbol-key)
		(goto-char (match-end 0))
		(c-put-font-lock-face (match-beginning 0)
				      (point)
				      'font-lock-function-name-face)
		(c-forward-syntactic-ws))

	      ;; There's another argument if a colon follows.
	      (eq (char-after) ?:)))
      (forward-char)
      (setq first nil))))

(defun c-font-lock-objc-methods (limit)
  ;; Fontify method declarations in Objective-C.  Nil is always
  ;; returned.
  ;;
  ;; This function might do hidden buffer changes.

  (let (;; The font-lock package in Emacs is known to clobber
	;; `parse-sexp-lookup-properties' (when it exists).
	(parse-sexp-lookup-properties
	 (cc-eval-when-compile
	   (boundp 'parse-sexp-lookup-properties))))

    (c-find-decl-spots
     limit
     "[-+]"
     nil
     (lambda (match-pos inside-macro)
       (forward-char)
       (c-font-lock-objc-method))))
  nil)

(c-override-default-keywords 'objc-font-lock-keywords)

(defconst objc-font-lock-keywords-1 (c-lang-const c-matchers-1 objc)
  "Minimal font locking for Objective-C mode.
Fontifies only compiler directives (in addition to the syntactic
fontification of strings and comments).")

(defconst objc-font-lock-keywords-2 (c-lang-const c-matchers-2 objc)
  "Fast normal font locking for Objective-C mode.
In addition to `objc-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `objc-font-lock-extra-types', and the doc
comment styles specified by `c-doc-comment-style'.")

(defconst objc-font-lock-keywords-3 (c-lang-const c-matchers-3 objc)
  "Accurate normal font locking for Objective-C mode.
Like `objc-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `objc-font-lock-extra-types'.")

(defvar objc-font-lock-keywords objc-font-lock-keywords-3
  "Default expressions to highlight in Objective-C mode.")

(defun objc-font-lock-keywords-2 ()
  (c-compose-keywords-list objc-font-lock-keywords-2))
(defun objc-font-lock-keywords-3 ()
  (c-compose-keywords-list objc-font-lock-keywords-3))
(defun objc-font-lock-keywords ()
  (c-compose-keywords-list objc-font-lock-keywords))

;; Kludge to override the default value that
;; `objc-font-lock-extra-types' might have gotten from the font-lock
;; package.  The value replaced here isn't relevant now anyway since
;; those types are builtin and therefore listed directly in
;; `c-primitive-type-kwds'.
(when (equal (sort (append objc-font-lock-extra-types nil) 'string-lessp)
	     '("BOOL" "Class" "IMP" "SEL"))
  (setq objc-font-lock-extra-types
	(cc-eval-when-compile (list (concat "[" c-upper "]\\sw*")))))


;;; Java.

(c-override-default-keywords 'java-font-lock-keywords)

(defconst java-font-lock-keywords-1 (c-lang-const c-matchers-1 java)
  "Minimal font locking for Java mode.
Fontifies nothing except the syntactic fontification of strings and
comments.")

(defconst java-font-lock-keywords-2 (c-lang-const c-matchers-2 java)
  "Fast normal font locking for Java mode.
In addition to `java-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `java-font-lock-extra-types', and the doc
comment styles specified by `c-doc-comment-style'.")

(defconst java-font-lock-keywords-3 (c-lang-const c-matchers-3 java)
  "Accurate normal font locking for Java mode.
Like `java-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `java-font-lock-extra-types'.")

(defvar java-font-lock-keywords java-font-lock-keywords-3
  "Default expressions to highlight in Java mode.")

(defun java-font-lock-keywords-2 ()
  (c-compose-keywords-list java-font-lock-keywords-2))
(defun java-font-lock-keywords-3 ()
  (c-compose-keywords-list java-font-lock-keywords-3))
(defun java-font-lock-keywords ()
  (c-compose-keywords-list java-font-lock-keywords))


;;; CORBA IDL.

(c-override-default-keywords 'idl-font-lock-keywords)

(defconst idl-font-lock-keywords-1 (c-lang-const c-matchers-1 idl)
  "Minimal font locking for CORBA IDL mode.
Fontifies nothing except the syntactic fontification of strings and
comments.")

(defconst idl-font-lock-keywords-2 (c-lang-const c-matchers-2 idl)
  "Fast normal font locking for CORBA IDL mode.
In addition to `idl-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `idl-font-lock-extra-types', and the doc comment
styles specified by `c-doc-comment-style'.")

(defconst idl-font-lock-keywords-3 (c-lang-const c-matchers-3 idl)
  "Accurate normal font locking for CORBA IDL mode.
Like `idl-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `idl-font-lock-extra-types'.")

(defvar idl-font-lock-keywords idl-font-lock-keywords-3
  "Default expressions to highlight in CORBA IDL mode.")

(defun idl-font-lock-keywords-2 ()
  (c-compose-keywords-list idl-font-lock-keywords-2))
(defun idl-font-lock-keywords-3 ()
  (c-compose-keywords-list idl-font-lock-keywords-3))
(defun idl-font-lock-keywords ()
  (c-compose-keywords-list idl-font-lock-keywords))


;;; Pike.

(c-override-default-keywords 'pike-font-lock-keywords)

(defconst pike-font-lock-keywords-1 (c-lang-const c-matchers-1 pike)
  "Minimal font locking for Pike mode.
Fontifies only preprocessor directives (in addition to the syntactic
fontification of strings and comments).")

(defconst pike-font-lock-keywords-2 (c-lang-const c-matchers-2 pike)
  "Fast normal font locking for Pike mode.
In addition to `pike-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `pike-font-lock-extra-types', and the doc
comment styles specified by `c-doc-comment-style'.")

(defconst pike-font-lock-keywords-3 (c-lang-const c-matchers-3 pike)
  "Accurate normal font locking for Pike mode.
Like `pike-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `pike-font-lock-extra-types'.")

(defvar pike-font-lock-keywords pike-font-lock-keywords-3
  "Default expressions to highlight in Pike mode.")

(defun pike-font-lock-keywords-2 ()
  (c-compose-keywords-list pike-font-lock-keywords-2))
(defun pike-font-lock-keywords-3 ()
  (c-compose-keywords-list pike-font-lock-keywords-3))
(defun pike-font-lock-keywords ()
  (c-compose-keywords-list pike-font-lock-keywords))


;;; Doc comments.

(defun c-font-lock-doc-comments (prefix limit keywords)
  ;; Fontify the comments between the point and LIMIT whose start
  ;; matches PREFIX with `c-doc-face-name'.  Assumes comments have been
  ;; fontified with `font-lock-comment-face' already.  nil is always
  ;; returned.
  ;;
  ;; After the fontification of a matching comment, fontification
  ;; according to KEYWORDS is applied inside it.  It's a list like
  ;; `font-lock-keywords' except that anchored matches and eval
  ;; clauses aren't supported and that some abbreviated forms can't be
  ;; used.  The buffer is narrowed to the comment while KEYWORDS is
  ;; applied; leading comment starters are included but trailing
  ;; comment enders for block comment are not.
  ;;
  ;; Note that faces added through KEYWORDS should never replace the
  ;; existing `c-doc-face-name' face since the existence of that face
  ;; is used as a flag in other code to skip comments.
  ;;
  ;; This function might do hidden buffer changes.

  (let (comment-beg region-beg)
    (if (eq (get-text-property (point) 'face)
	    'font-lock-comment-face)
	;; Handle the case when the fontified region starts inside a
	;; comment.
	(let ((range (c-literal-limits)))
	  (setq region-beg (point))
	  (when range
	    (goto-char (car range)))
	  (when (looking-at prefix)
	    (setq comment-beg (point)))))

    (while (or
	    comment-beg

	    ;; Search for the prefix until a match is found at the start
	    ;; of a comment.
	    (while (when (re-search-forward prefix limit t)
		     (setq comment-beg (match-beginning 0))
		     (or (not (c-got-face-at comment-beg
					     c-literal-faces))
			 (and (/= comment-beg (point-min))
			      (c-got-face-at (1- comment-beg)
					     c-literal-faces))))
	      (setq comment-beg nil))
	    (setq region-beg comment-beg))

      (if (eq (elt (parse-partial-sexp comment-beg (+ comment-beg 2)) 7) t)
	  ;; Collect a sequence of doc style line comments.
	  (progn
	    (goto-char comment-beg)
	    (while (and (progn
			  (c-forward-single-comment)
			  (skip-syntax-forward " ")
			  (< (point) limit))
			(looking-at prefix))))
	(goto-char comment-beg)
	(c-forward-single-comment))
      (if (> (point) limit) (goto-char limit))
      (setq comment-beg nil)

      (let ((region-end (point))
	    (keylist keywords) keyword matcher highlights)
	(c-put-font-lock-face region-beg region-end c-doc-face-name)
	(save-restriction
	  ;; Narrow to the doc comment.  Among other things, this
	  ;; helps by making "^" match at the start of the comment.
	  ;; Do not include a trailing block comment ender, though.
	  (and (> region-end (1+ region-beg))
	       (progn (goto-char region-end)
		      (backward-char 2)
		      (looking-at "\\*/"))
	       (setq region-end (point)))
	  (narrow-to-region region-beg region-end)

	  (while keylist
	    (setq keyword (car keylist)
		  keylist (cdr keylist)
		  matcher (car keyword))
	    (goto-char region-beg)
	    (while (if (stringp matcher)
		       (re-search-forward matcher region-end t)
		     (funcall matcher region-end))
	      (setq highlights (cdr keyword))
	      (if (consp (car highlights))
		  (while highlights
		    (font-lock-apply-highlight (car highlights))
		    (setq highlights (cdr highlights)))
		(font-lock-apply-highlight highlights))))

	  (goto-char region-end)))))
  nil)
(put 'c-font-lock-doc-comments 'lisp-indent-function 2)

(defun c-find-invalid-doc-markup (regexp limit)
  ;; Used to fontify invalid markup in doc comments after the correct
  ;; ones have been fontified: Find the first occurence of REGEXP
  ;; between the point and LIMIT that only is fontified with
  ;; `c-doc-face-name'.  If a match is found then submatch 0 surrounds
  ;; the first char and t is returned, otherwise nil is returned.
  ;;
  ;; This function might do hidden buffer changes.
  (let (start)
    (while (if (re-search-forward regexp limit t)
	       (not (eq (get-text-property
			 (setq start (match-beginning 0)) 'face)
			c-doc-face-name))
	     (setq start nil)))
    (when start
      (store-match-data (list (copy-marker start)
			      (copy-marker (1+ start))))
      t)))

(defconst javadoc-font-lock-doc-comments
  `(("{@[a-z]+[^}\n\r]*}"		; "{@foo ...}" markup.
     0 ,c-doc-markup-face-name prepend nil)
    ("^\\(/\\*\\)?\\(\\s \\|\\*\\)*\\(@[a-z]+\\)" ; "@foo ..." markup.
     3 ,c-doc-markup-face-name prepend nil)
    (,(concat "</?\\sw"			; HTML tags.
	      "\\("
	      (concat "\\sw\\|\\s \\|[=\n\r*.:]\\|"
		      "\"[^\"]*\"\\|'[^']*'")
	      "\\)*>")
     0 ,c-doc-markup-face-name prepend nil)
    ("&\\(\\sw\\|[.:]\\)+;"		; HTML entities.
     0 ,c-doc-markup-face-name prepend nil)
    ;; Fontify remaining markup characters as invalid.  Note
    ;; that the Javadoc spec is hazy about when "@" is
    ;; allowed in non-markup use.
    (,(lambda (limit)
	(c-find-invalid-doc-markup "[<>&]\\|{@" limit))
     0 'font-lock-warning-face prepend nil)))

(defconst javadoc-font-lock-keywords
  `((,(lambda (limit)
	(c-font-lock-doc-comments "/\\*\\*" limit
	  javadoc-font-lock-doc-comments)))))

(defconst autodoc-decl-keywords
  ;; Adorned regexp matching the keywords that introduce declarations
  ;; in Pike Autodoc.
  (cc-eval-when-compile
    (c-make-keywords-re t '("@decl" "@elem" "@index" "@member") 'pike-mode)))

(defconst autodoc-decl-type-keywords
  ;; Adorned regexp matching the keywords that are followed by a type.
  (cc-eval-when-compile
    (c-make-keywords-re t '("@elem" "@member") 'pike-mode)))

(defun autodoc-font-lock-line-markup (limit)
  ;; Fontify all line oriented keywords between the point and LIMIT.
  ;; Nil is always returned.
  ;;
  ;; This function might do hidden buffer changes.

  (let ((line-re (concat "^\\(\\(/\\*!\\|\\s *\\("
			 c-current-comment-prefix
			 "\\)\\)\\s *\\)@[A-Za-z_-]+\\(\\s \\|$\\)"))
	(markup-faces (list c-doc-markup-face-name c-doc-face-name)))

    (while (re-search-forward line-re limit t)
      (goto-char (match-end 1))

      (if (looking-at autodoc-decl-keywords)
	  (let* ((kwd-pos (point))
		 (start (match-end 1))
		 (pos start)
		 end)

	    (c-put-font-lock-face (point) pos markup-faces)

	    ;; Put a declaration end mark at the markup keyword and
	    ;; remove the faces from the rest of the line so that it
	    ;; gets refontified as a declaration later on by
	    ;; `c-font-lock-declarations'.
	    (c-put-char-property (1- pos) 'c-type 'c-decl-end)
	    (goto-char pos)
	    (while (progn
		     (end-of-line)
		     (setq end (point))
		     (and (eq (char-before) ?@)
			  (not (eobp))
			  (progn (forward-char)
				 (skip-syntax-forward " ")
				 (looking-at c-current-comment-prefix))))
	      (goto-char (match-end 0))
	      (c-remove-font-lock-face pos (1- end))
	      (c-put-font-lock-face (1- end) end markup-faces)
	      (setq pos (point)))

	    ;; Include the final newline in the removed area.  This
	    ;; has no visual effect but it avoids some tricky special
	    ;; cases in the testsuite wrt the differences in string
	    ;; fontification in Emacs vs XEmacs.
	    (c-remove-font-lock-face pos (min (1+ (point)) (point-max)))

	    ;; Must handle string literals explicitly inside the declaration.
	    (goto-char start)
	    (while (re-search-forward
		    "\"\\([^\\\"]\\|\\\\.\\)*\"\\|'\\([^\\']\\|\\\\.\\)*'"
		    end 'move)
	      (c-put-font-lock-string-face (match-beginning 0)
					   (point)))

	    ;; Fontify types after keywords that always are followed
	    ;; by them.
	    (goto-char kwd-pos)
	    (when (looking-at autodoc-decl-type-keywords)
	      (c-fontify-types-and-refs ((c-promote-possible-types t))
		(goto-char start)
		(c-forward-syntactic-ws)
		(c-forward-type))))

	;; Mark each whole line as markup, as long as the logical line
	;; continues.
	(while (progn
		 (c-put-font-lock-face (point)
				       (progn (end-of-line) (point))
				       markup-faces)
		 (and (eq (char-before) ?@)
		      (not (eobp))
		      (progn (forward-char)
			     (skip-syntax-forward " ")
			     (looking-at c-current-comment-prefix))))
	  (goto-char (match-end 0))))))

  nil)

(defconst autodoc-font-lock-doc-comments
  `(("@\\(\\w+{\\|\\[\\([^\]@\n\r]\\|@@\\)*\\]\\|[@}]\\|$\\)"
     ;; In-text markup.
     0 ,c-doc-markup-face-name prepend nil)
    (autodoc-font-lock-line-markup)
    ;; Fontify remaining markup characters as invalid.
    (,(lambda (limit)
	(c-find-invalid-doc-markup "@" limit))
     0 'font-lock-warning-face prepend nil)
    ))

(defun autodoc-font-lock-keywords ()
  ;; Note that we depend on that `c-current-comment-prefix' has got
  ;; its proper value here.
  ;;
  ;; This function might do hidden buffer changes.

  ;; The `c-type' text property with `c-decl-end' is used to mark the
  ;; end of the `autodoc-decl-keywords' occurrences to fontify the
  ;; following declarations.
  (setq c-type-decl-end-used t)

  `((,(lambda (limit)
	(c-font-lock-doc-comments "/[*/]!" limit
	  autodoc-font-lock-doc-comments)))))


;; AWK.

;; Awk regexps written with help from Peter Galbraith
;; <galbraith@mixing.qc.dfo.ca>.
;; Take GNU Emacs's 'words out of the following regexp-opts.  They dont work
;; in Xemacs 21.4.4.  acm 2002/9/19.
(eval-after-load "cc-awk"               ; Evaluate while loading cc-fonts
  `(defconst awk-font-lock-keywords     ; Evaluate after loading cc-awk
     ',(eval-when-compile               ; Evaluate while compiling cc-fonts
	 (list
	  ;; Function names.
	  '("^\\s *\\(func\\(tion\\)?\\)\\>\\s *\\(\\sw+\\)?"
	    (1 font-lock-keyword-face) (3 font-lock-function-name-face nil t))
	  ;;
	  ;; Variable names.
	  (cons
	   (concat "\\<"
		   (regexp-opt
		    '("ARGC" "ARGIND" "ARGV" "BINMODE" "CONVFMT" "ENVIRON"
		      "ERRNO" "FIELDWIDTHS" "FILENAME" "FNR" "FS" "IGNORECASE"
		      "LINT" "NF" "NR" "OFMT" "OFS" "ORS" "PROCINFO" "RLENGTH"
		      "RS" "RSTART" "RT" "SUBSEP" "TEXTDOMAIN") t) "\\>")
	   'font-lock-variable-name-face)

	  ;; Special file names.  (acm, 2002/7/22)
	  ;; The following regexp was created by first evaluating this in GNU Emacs 21.1:
	  ;; (regexp-opt '("/dev/stdin" "/dev/stdout" "/dev/stderr" "/dev/fd/n" "/dev/pid"
	  ;;                 "/dev/ppid" "/dev/pgrpid" "/dev/user") 'words)
	  ;; , removing the "?:" from each "\\(?:" (for backward compatibility with older Emacsen)
	  ;; , replacing the "n" in "dev/fd/n" with "[0-9]+"
	  ;; , removing the unwanted \\< at the beginning, and finally filling out the
	  ;; regexp so that a " must come before, and either a " or heuristic stuff after.
	  ;; The surrounding quotes are fontified along with the filename, since, semantically,
	  ;; they are an indivisible unit.
	  '("\\(\"/dev/\\(fd/[0-9]+\\|p\\(\\(\\(gr\\)?p\\)?id\\)\\|\
std\\(err\\|in\\|out\\)\\|user\\)\\)\\>\
\\(\\(\"\\)\\|\\([^\"/\n\r][^\"\n\r]*\\)?$\\)"
	    (1 font-lock-variable-name-face t)
	    (8 font-lock-variable-name-face t t))
	  ;; Do the same (almost) with
	  ;; (regexp-opt '("/inet/tcp/lport/rhost/rport" "/inet/udp/lport/rhost/rport"
	  ;;                 "/inet/raw/lport/rhost/rport") 'words)
	  ;; This cannot be combined with the above pattern, because the match number
	  ;; for the (optional) closing \" would then exceed 9.
	  '("\\(\"/inet/\\(\\(raw\\|\\(tc\\|ud\\)p\\)/lport/rhost/rport\\)\\)\\>\
\\(\\(\"\\)\\|\\([^\"/\n\r][^\"\n\r]*\\)?$\\)"
	    (1 font-lock-variable-name-face t)
	    (6 font-lock-variable-name-face t t))

	  ;; Keywords.
	  (concat "\\<"
		  (regexp-opt
		   '("BEGIN" "END" "break" "continue" "delete" "do" "else"
		     "exit" "for" "getline" "if" "in" "next" "nextfile"
		     "return" "while")
		   t) "\\>")

	  ;; Builtins.
	  `(eval . (list
		    ,(concat
		      "\\<"
		      (regexp-opt
		       '("adump" "and" "asort" "atan2" "bindtextdomain" "close"
			 "compl" "cos" "dcgettext" "exp" "extension" "fflush"
			 "gensub" "gsub" "index" "int" "length" "log" "lshift"
			 "match" "mktime" "or" "print" "printf" "rand" "rshift"
			 "sin" "split" "sprintf" "sqrt" "srand" "stopme"
			 "strftime" "strtonum" "sub" "substr"  "system"
			 "systime" "tolower" "toupper" "xor") t)
		      "\\>")
		    0 c-preprocessor-face-name))

	  ;; gawk debugging keywords.  (acm, 2002/7/21)
	  ;; (Removed, 2003/6/6.  These functions are now fontified as built-ins)
;;	(list (concat "\\<" (regexp-opt '("adump" "stopme") t) "\\>")
;;	   0 'font-lock-warning-face)

	  ;; User defined functions with an apparent spurious space before the
	  ;; opening parenthesis.  acm, 2002/5/30.
	  `(,(concat "\\(\\w\\|_\\)" c-awk-escaped-nls* "\\s "
		     c-awk-escaped-nls*-with-space* "(")
	    (0 'font-lock-warning-face))

	  ;; Space after \ in what looks like an escaped newline.  2002/5/31
	  '("\\\\\\s +$" 0 font-lock-warning-face t)

	  ;; Unbalanced string (") or regexp (/) delimiters.  2002/02/16.
	  '("\\s|" 0 font-lock-warning-face t nil)
	  ;; gawk 3.1 localizable strings ( _"translate me!").  2002/5/21
	  '("\\(_\\)\\s|" 1 font-lock-warning-face)
	  '("\\(_\\)\\s\"" 1 font-lock-string-face) ; FIXME! not for XEmacs. 2002/10/6
	  ))
     "Default expressions to highlight in AWK mode."))


(cc-provide 'cc-fonts)

;;; cc-fonts.el ends here
