;;; health-chart-render.el --- Interchangeable rendering backends driven by templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Lisp prepares the data, a template draws it.  `health-chart-spec'
;; turns data into a neutral chart spec (chartspec/v1); a BACKEND fills
;; its template for the chart's kind with that spec and runs its tool:
;;
;;   vega-lite  templates/vega-lite/KIND.vl.json -> vl2svg / vl2png /
;;              vl2pdf (PNG and PDF fall back to vl2svg | rsvg-convert
;;              when node-canvas is missing); format vega-lite returns
;;              the filled JSON itself
;;   gnuplot    templates/gnuplot/KIND.gp -> gnuplot with the svg,
;;              pngcairo, pdfcairo or dumb (text) terminal
;;   text       the native unicode renderers: the last-resort terminal
;;              fallback, and the only renderer of table, sparkline,
;;              scorecard and cohort
;;   svg        the native SVG renderers: obsolete, never chosen by
;;              default, kept for callers that ask for them by name
;;
;; `health-chart-backends' is the registry (name -> plist).  Selection,
;; when the caller says :backend auto (the default): a GUI frame (or an
;; image format) takes the first of `health-chart-graphic-backends' that
;; is available and has a template for the kind, a terminal the first of
;; `health-chart-terminal-backends'; failing both, native text.
;;
;; Entry points: `health-chart-render' (an image object in a GUI, else
;; text; or any format as a string), `health-chart-write' (to a file,
;; format from the extension), `health-chart-render-explain' (the exact
;; argv and generated program, pure), `health-chart-templates'.
;; Programs reach tools on stdin or in temporary files; no shell is
;; involved, so no value is ever shell-interpolated.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-kind)
(require 'health-chart-spec)
(require 'health-chart-template)

(define-error 'health-chart-backend-error
  "health-chart: rendering backend failed" 'health-chart-error)

;; -----------------------------------------------------------------------
;; Customization
;; -----------------------------------------------------------------------

(defcustom health-chart-backend 'auto
  "Rendering backend: `auto', `vega-lite', `gnuplot', `text' or `svg'.
`auto' picks per chart: in a frame that shows images the first of
`health-chart-graphic-backends' that is installed and has a template for
the kind, in a terminal the first of `health-chart-terminal-backends',
else native text.  `svg' (the native SVG renderer) is obsolete.
Override per call with the :backend prop."
  :type '(choice (const auto) (const vega-lite) (const gnuplot) (const text)
                 (const :tag "svg (native, obsolete)" svg))
  :group 'health-charts)

(defcustom health-chart-graphic-backends '(vega-lite gnuplot)
  "Backends `auto' tries, in order, where images can be shown."
  :type '(repeat symbol)
  :group 'health-charts)

(defcustom health-chart-terminal-backends '(gnuplot text)
  "Backends `auto' tries, in order, in a terminal (text output)."
  :type '(repeat symbol)
  :group 'health-charts)

(defcustom health-chart-image-scale 1
  "Pixel ratio of PNG output: 2 renders a 720px-wide chart 1440 pixels wide.
Override per call with the :scale prop."
  :type 'number
  :group 'health-charts)

(defcustom health-chart-vl2svg-command nil
  "Command (a list: program and arguments) rendering Vega-Lite to SVG.
nil: vl2svg on variable `exec-path', else
npx -p vega -p vega-lite -p vega-cli vl2svg."
  :type '(choice (const :tag "Auto" nil) (repeat string))
  :group 'health-charts)

(defcustom health-chart-vl2png-command nil
  "Command (a list) rendering Vega-Lite to PNG; nil for vl2png (or npx).
vl2png needs node-canvas; without it PNG comes from vl2svg piped
through `health-chart-rsvg-convert-command'."
  :type '(choice (const :tag "Auto" nil) (repeat string))
  :group 'health-charts)

(defcustom health-chart-vl2pdf-command nil
  "Command (a list) rendering Vega-Lite to PDF; nil for vl2pdf (or npx).
Like vl2png it needs node-canvas, and falls back to rsvg-convert."
  :type '(choice (const :tag "Auto" nil) (repeat string))
  :group 'health-charts)

(defcustom health-chart-vega-lite-raster 'auto
  "How the vega-lite backend makes PNG and PDF.
`auto': vl2png / vl2pdf, falling back to vl2svg + rsvg-convert when they
fail (node-canvas missing) -- the fallback is then remembered for the
session; `vl2png': only vl2png / vl2pdf; `rsvg-convert': always vl2svg +
rsvg-convert."
  :type '(choice (const auto) (const vl2png) (const rsvg-convert))
  :group 'health-charts)

(defcustom health-chart-rsvg-convert-command '("rsvg-convert")
  "Command (a list) converting SVG on stdin to PNG or PDF on stdout."
  :type '(repeat string)
  :group 'health-charts)

(defcustom health-chart-gnuplot-command '("gnuplot")
  "Command (a list) running a gnuplot script read from stdin."
  :type '(repeat string)
  :group 'health-charts)

(defcustom health-chart-tool-directories
  (pcase system-type
    ('windows-nt
     (delq nil (list (when-let* ((pf (getenv "ProgramFiles")))
                       (expand-file-name "gnuplot/bin" pf))
                     (when-let* ((appdata (getenv "APPDATA")))
                       (expand-file-name "npm" appdata)))))
    ('darwin '("/opt/homebrew/bin" "/usr/local/bin")))
  "Directories searched for tools after variable `exec-path'.
A GUI Emacs often starts with a shorter PATH than a shell: on macOS it
misses Homebrew, on Windows the gnuplot installer and npm's global
directory are not always on PATH.  Tools are looked up with
`executable-find', so on Windows gnuplot finds gnuplot.exe and vl2svg
finds npm's vl2svg.cmd shim."
  :type '(repeat directory)
  :group 'health-charts)

(defcustom health-chart-render-timeout 60
  "Seconds a backend tool may run before it is abandoned."
  :type 'natnum
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Registry
;; -----------------------------------------------------------------------

(defvar health-chart-backends
  '((vega-lite
     :doc "Vega-Lite templates rendered by vl2svg/vl2png/vl2pdf (npm vega-cli)."
     :language json :extension ".vl.json" :graphic t
     :formats (svg png pdf vega-lite)
     :available-p health-chart-vega-lite-available-p
     :explain health-chart-vega-lite-explain
     :render health-chart-vega-lite-render
     :install "npm install -g vega vega-lite vega-cli (needs Node.js; see the README's Requirements)")
    (gnuplot
     :doc "gnuplot templates rendered with the svg, pngcairo, pdfcairo or dumb terminal."
     :language gnuplot :extension ".gp" :graphic t
     :formats (svg png pdf text)
     :available-p health-chart-gnuplot-available-p
     :explain health-chart-gnuplot-explain
     :render health-chart-gnuplot-render
     :install "gnuplot 5.4 or later: apt install gnuplot-nox, brew install gnuplot, or winget install gnuplot.gnuplot")
    (text
     :doc "Native unicode renderers: last-resort terminal fallback; every kind."
     :native :text :formats (text)
     :available-p always)
    (svg
     :doc "Native SVG renderers (obsolete: never chosen by default, no new features)."
     :native :svg :obsolete t :formats (svg)
     :available-p always))
  "Rendering backends: (NAME . PLIST).
PLIST keys: :doc; :formats, the formats it writes (svg png pdf text
vega-lite); :available-p, a function of no arguments; for template
backends :language (json or gnuplot) and :extension (of its template
files), :explain (SPEC FORMAT &optional OUT) -> plan with the generated
:program and the exact :steps (argv and stdin), and :render (SPEC
FORMAT OUT) -> OUT, or the output as a string when OUT is nil; for
native backends :native, the `health-chart-kinds' renderer key.")

(defconst health-chart-formats
  '((svg . ".svg") (png . ".png") (pdf . ".pdf") (text . ".txt") (vega-lite . ".vl.json"))
  "Output formats and their file extensions.")

(defun health-chart--backend (name)
  "The registry plist of backend NAME, or signal."
  (or (alist-get name health-chart-backends)
      (signal 'health-chart-backend-error
              (list (format "unknown backend %S; use auto or one of %s" name
                            (mapconcat (lambda (b) (symbol-name (car b))) health-chart-backends ", "))
                    :code "unknown_backend" :backend name))))

(defun health-chart-backend-available-p (name)
  "Non-nil when backend NAME's tools are installed."
  (let ((fn (plist-get (health-chart--backend name) :available-p)))
    (and fn (funcall fn) t)))

(defun health-chart-template-for (backend kind)
  "Return the template file of BACKEND for KIND, or nil (always for natives)."
  (when-let* ((ext (plist-get (health-chart--backend backend) :extension)))
    (health-chart-template-find backend kind ext)))

;;;###autoload
(defun health-chart-templates ()
  "Every available template as (:backend :kind :path :source), backend order.
:source is user for a file in `health-chart-template-directories', else
bundled.  A user's file shadows the bundled template of the same kind."
  (cl-loop for (name . plist) in health-chart-backends
           for ext = (plist-get plist :extension)
           when ext
           append (mapcar (lambda (entry)
                            (list :backend name :kind (car entry) :path (cdr entry)
                                  :source (if (file-in-directory-p (cdr entry)
                                                                   health-chart-template-bundled-directory)
                                              'bundled 'user)))
                          (health-chart-template-list name ext))))

(defun health-chart--template-kind-p (kind)
  "Non-nil when some template backend has a template for KIND."
  (seq-some (lambda (b) (health-chart-template-for (car b) kind)) health-chart-backends))

(defun health-chart--template-kind-entry (kind)
  "A registry entry for template-only KIND, or nil when no template exists."
  (when (health-chart--template-kind-p kind)
    (list :shape 'measurements :template-only t
          :doc (format "Template-only kind %s (measurements)." kind))))

(add-hook 'health-chart-kind-fallback-functions #'health-chart--template-kind-entry)

;; -----------------------------------------------------------------------
;; The spec
;; -----------------------------------------------------------------------

(defun health-chart--spec-builder (kind)
  "The spec body builder of KIND: its :spec, else a generic one by shape."
  (let ((entry (health-chart--kind kind)))
    (or (plist-get entry :spec)
        (if (eq (plist-get entry :shape) 'indicators)
            #'health-chart-spec-generic-indicators
          #'health-chart-spec-generic))))

;;;###autoload
(defun health-chart-spec (kind data &rest props)
  "The chartspec/v1 plist for KIND over DATA under PROPS.  Pure.
DATA is anything KIND's shape accepts (biomarker/v1 JSON or envelope,
plists, alists); it is normalized and validated first.  PROPS: :person
:marker :title :subtitle :theme (light/dark) :pixel-width :pixel-height
:width/:height (text columns/rows) :ref :optimal, and per-kind props.
`health-chart-spec-to-json' gives the JSON form; docs/chartspec.md the
schema."
  (let ((data (health-chart-normalize kind data)))
    (apply #'health-chart-validate kind data (health-chart--plist-drop props :backend :format))
    (health-chart-spec-build kind data props (health-chart--spec-builder kind))))

;; -----------------------------------------------------------------------
;; Selection
;; -----------------------------------------------------------------------

(defun health-chart--graphic-context-p ()
  "Non-nil when the selected frame can show SVG or PNG images."
  (and (display-images-p)
       (or (image-type-available-p 'svg) (image-type-available-p 'png))))

(defun health-chart--image-format ()
  "The image format this Emacs displays: png when it lacks librsvg, else svg."
  (if (and (not (image-type-available-p 'svg)) (image-type-available-p 'png)) 'png 'svg))

(defun health-chart--supports-p (backend kind format)
  "Non-nil when BACKEND can draw KIND in FORMAT (nil: any of its formats)."
  (let ((plist (health-chart--backend backend)))
    (and (or (null format) (memq format (plist-get plist :formats)))
         (if (plist-get plist :native)
             (fboundp (plist-get (health-chart--kind kind) (plist-get plist :native)))
           (health-chart-template-for backend kind)))))

(defun health-chart-select-backend (kind &optional backend format)
  "(BACKEND FORMAT REASON) for drawing KIND.
BACKEND nil means `health-chart-backend'; FORMAT nil means the natural
format: svg where images show (png when this Emacs was built without
librsvg; text for native text), text in a terminal.  REASON says why,
for `health-chart-explain'."
  (let* ((requested (or backend health-chart-backend))
         (graphic (if format (not (eq format 'text)) (health-chart--graphic-context-p))))
    (if (not (eq requested 'auto))
        (let* ((plist (health-chart--backend requested))
               (formats (plist-get plist :formats))
               (fmt (or format
                        (cond ((and graphic (memq (health-chart--image-format) formats))
                               (health-chart--image-format))
                              ((memq 'text formats) 'text)
                              (t (car formats))))))
          (when (and (plist-get plist :native)
                     (not (functionp (plist-get (health-chart--kind kind) (plist-get plist :native)))))
            (signal 'health-chart-backend-error
                    (list (format "backend %s has no renderer for %s, a kind drawn by templates only; use %s"
                                  requested kind
                                  (mapconcat #'symbol-name
                                             (seq-filter (lambda (b) (and (assq b health-chart-backends)
                                                                          (health-chart-template-for b kind)))
                                                         health-chart-graphic-backends)
                                             " or "))
                          :code "unsupported_kind" :backend requested :kind kind)))
          (unless (memq fmt formats)
            (signal 'health-chart-backend-error
                    (list (format "backend %s cannot write %s; it writes %s" requested fmt
                                  (mapconcat #'symbol-name formats ", "))
                          :code "unsupported_format" :backend requested :format fmt)))
          (list requested fmt (format "requested %s" requested)))
      (let* ((order (if graphic health-chart-graphic-backends health-chart-terminal-backends))
             (want (or format (if graphic (health-chart--image-format) 'text)))
             (pick (seq-find (lambda (b)
                               (and (assq b health-chart-backends)
                                    (health-chart--supports-p b kind want)
                                    (health-chart-backend-available-p b)))
                             order)))
        (cond
         (pick (list pick want (format "auto: %s; %s is the first of %s installed with a %s template"
                                       (if graphic "images can be shown" "terminal")
                                       pick order kind)))
         ((and (or (null format) (memq want '(text svg)))
               (health-chart--supports-p 'text kind 'text))
          (list 'text 'text (format "auto: no backend of %s is installed with a %s template; native text"
                                    order kind)))
         (t (signal 'health-chart-backend-error
                    (list (format "no installed backend writes %s %s; install one of %s (see `health-chart-doctor')"
                                  kind want order)
                          :code "no_backend" :kind kind :format want))))))))

;; -----------------------------------------------------------------------
;; Running tools
;; -----------------------------------------------------------------------

(defun health-chart-executable (program)
  "The absolute file name of PROGRAM, or nil when it is not installed.
PROGRAM is a name looked up with `executable-find' on variable
`exec-path' then `health-chart-tool-directories' (Windows suffixes such
as .exe and .cmd included), or an absolute file name."
  (or (executable-find program)
      (let ((exec-path (append health-chart-tool-directories exec-path)))
        (executable-find program))))

(defun health-chart--command (custom default-exe &rest npx-tail)
  "Command list: CUSTOM, else DEFAULT-EXE when found, else npx with NPX-TAIL."
  (or custom
      (and (health-chart-executable default-exe) (list default-exe))
      (append '("npx" "--yes" "-p" "vega" "-p" "vega-lite" "-p" "vega-cli") npx-tail)))

(defvar health-chart--vl-canvas-broken nil
  "Non-nil once vl2png/vl2pdf failed and rsvg-convert replaced them.")

(defun health-chart-vega-lite-available-p ()
  "Non-nil when a Vega-Lite renderer is configured or vl2svg is installed."
  (let ((cmd (health-chart--command health-chart-vl2svg-command "vl2svg" "vl2svg")))
    (and (not (equal (car cmd) "npx")) (health-chart-executable (car cmd)) t)))

(defun health-chart-gnuplot-available-p ()
  "Non-nil when gnuplot is installed."
  (and (health-chart-executable (car health-chart-gnuplot-command)) t))

(defun health-chart--rsvg-available-p ()
  "Non-nil when rsvg-convert is installed."
  (and (health-chart-executable (car health-chart-rsvg-convert-command)) t))

(defun health-chart--run (argv input &optional binary writes-file)
  "Run ARGV with INPUT (a string) on stdin; return stdout as a string.
BINARY keeps stdout as raw bytes; text output may end lines in CRLF
\(gnuplot on Windows).  The program is resolved with
`health-chart-executable' and run directly, without a shell; on Windows
Emacs runs an npm .cmd shim through cmd.exe itself.  Signals
`health-chart-backend-error' with stderr when the tool is missing,
fails, times out, or writes nothing to stdout unless WRITES-FILE (the
tool writes its own output file).  gnuplot on Windows exits 0 after a
script error, so empty output is how that failure shows."
  (let ((exe (or (health-chart-executable (car argv))
                 (signal 'health-chart-backend-error
                         (list (format "cannot find %s; install it or customize the backend's command (see `health-chart-doctor')"
                                       (car argv))
                               :code "backend_missing" :argv argv))))
        (errors (generate-new-buffer " *health-chart-stderr*" t)))
    (unwind-protect
        (with-temp-buffer
          (set-buffer-multibyte (not binary))
          (let ((status (health-chart--call exe (cdr argv) input binary errors)))
            (when (and (eql status 0) (= (buffer-size) 0) (not writes-file))
              (signal 'health-chart-backend-error
                      (list (format "%s wrote no output: %s" (string-join argv " ")
                                    (string-trim (with-current-buffer errors (buffer-string))))
                            :code "backend_failed" :argv argv :exit 0)))
            (unless (eql status 0)
              (signal 'health-chart-backend-error
                      (if (eq status 'timeout)
                          (list (format "%s did not finish within %s seconds; raise `health-chart-render-timeout' or check the tool"
                                        (string-join argv " ") health-chart-render-timeout)
                                :code "backend_timeout" :argv argv)
                        (list (format "%s exited %s: %s" (string-join argv " ") status
                                      (string-trim (with-current-buffer errors (buffer-string))))
                              :code "backend_failed" :argv argv :exit status))))
            (buffer-string)))
      (kill-buffer errors))))

(defun health-chart--call (exe args input binary errors)
  "Run EXE with ARGS, INPUT on stdin, stdout into the current buffer.
BINARY keeps stdout as bytes, else it is decoded as UTF-8 with any line
ends; stderr goes to buffer ERRORS.  Return the exit status, or
`timeout' after `health-chart-render-timeout' seconds (the process is
then killed).  An asynchronous process, so the timeout holds even
while the tool blocks."
  (let* ((done nil)
         (process-environment (cons "LC_ALL=C.UTF-8" process-environment))
         (proc (make-process :name "health-chart" :buffer (current-buffer)
                             :command (cons exe args) :connection-type 'pipe
                             :coding (cons (if binary 'binary 'utf-8) 'utf-8-unix)
                             :stderr errors :noquery t
                             :sentinel (lambda (_proc _event) (setq done t))))
         (deadline (+ (float-time) health-chart-render-timeout)))
    (when-let* ((err (get-buffer-process errors)))
      (set-process-coding-system err 'utf-8 'utf-8-unix))
    (unwind-protect
        (progn
          ;; a tool may exit without reading stdin; on Windows the write
          ;; then fails, and its exit status is the answer
          (ignore-error error
            (process-send-string proc input)
            (process-send-eof proc))
          ;; the sentinel runs once stdout has been read to the end; under
          ;; load it can be starved, so a reaped child also ends the wait
          (while (and (not done) (process-live-p proc) (< (float-time) deadline))
            (accept-process-output proc 0.05))
          (if (or done (not (process-live-p proc)))
              (progn
                (while (accept-process-output proc 0.05))
                ;; stderr arrives on its own pipe; drain it too
                (when-let* ((err (get-buffer-process errors)))
                  (while (accept-process-output err 0.05)))
                (process-exit-status proc))
            'timeout))
      (when (process-live-p proc) (delete-process proc))
      (when-let* ((err (get-buffer-process errors))) (delete-process err)))))

(defun health-chart--write-bytes (string file)
  "Write STRING to FILE exactly (raw bytes when unibyte, else UTF-8)."
  (let ((coding-system-for-write (if (multibyte-string-p string) 'utf-8-unix 'binary)))
    (with-temp-file file
      (set-buffer-multibyte (multibyte-string-p string))
      (insert string))))

(defun health-chart--read-bytes (file)
  "Contents of FILE as raw bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'binary))
      (insert-file-contents-literally file))
    (buffer-string)))

(defun health-chart--pipe (commands program binary)
  "Return the output of PROGRAM fed through the plan COMMANDS in turn.
Each step's :argv reads the previous output on stdin.  BINARY keeps the
last output as bytes."
  (let ((input program) (n (length commands)) (i 0))
    (dolist (step commands)
      (cl-incf i)
      (setq input (health-chart--run (plist-get step :argv) input (and binary (= i n))
                                     (plist-get step :writes-file))))
    input))

(defun health-chart--pipe-or-svg-only (commands program binary format primary)
  "Run the fallback COMMANDS on PROGRAM as `health-chart--pipe' with BINARY.
When one of their tools (rsvg-convert) is missing, signal that FORMAT
cannot be made here but SVG can, naming PRIMARY, the direct tool's error."
  (condition-case err
      (health-chart--pipe commands program binary)
    (health-chart-backend-error
     (if (and (equal (plist-get (cddr err) :code) "backend_missing")
              (equal (car (plist-get (cddr err) :argv)) (car health-chart-rsvg-convert-command)))
         (signal 'health-chart-backend-error
                 (list (format "cannot write %s: %s; the fallback through rsvg-convert cannot run either (%s); install rsvg-convert, or write SVG, which needs neither"
                               format (cadr primary) (cadr err))
                       :code "backend_missing" :format format
                       :argv (plist-get (cddr err) :argv)))
       (signal (car err) (cdr err))))))

(defun health-chart--render-plan (plan format out)
  "Run PLAN (from a backend's explain) for FORMAT; write OUT or return a string.
A failing primary run falls back to PLAN's :fallback steps when present."
  (let* ((binary (memq format '(png pdf)))
         (output
          (if (null (plist-get plan :steps))
              (plist-get plan :program)
            (condition-case err
                (health-chart--pipe (plist-get plan :steps) (plist-get plan :program) binary)
              (health-chart-backend-error
               (if-let* ((fallback (plist-get plan :fallback)))
                   (prog1 (health-chart--pipe-or-svg-only fallback (plist-get plan :program)
                                                          binary format err)
                     (setq health-chart--vl-canvas-broken t))
                 (signal (car err) (cdr err))))))))
    (if out
        (progn (health-chart--write-bytes output out) out)
      output)))

;; -----------------------------------------------------------------------
;; vega-lite
;; -----------------------------------------------------------------------

(defun health-chart--template-program (backend spec format)
  "(FILE . PROGRAM): BACKEND's template for SPEC's kind filled for FORMAT."
  (let* ((plist (health-chart--backend backend))
         (kind (plist-get spec :kind))
         (file (or (health-chart-template-for backend kind)
                   (signal 'health-chart-backend-error
                           (list (format "no %s template for kind %s; add %s/%s%s to a directory of `health-chart-template-directories'"
                                         backend kind backend kind (plist-get plist :extension))
                                 :code "no_template" :backend backend :kind kind))))
         (context (append (list :data (plist-get spec :rows)
                                :format (symbol-name format)
                                :scale (or (plist-get spec :scale) 1))
                          spec)))
    (cons file (health-chart-template-fill (health-chart-template-read file) context
                                           (plist-get plist :language) file))))

(defun health-chart-vega-lite-explain (spec format &optional _out)
  "Return the vega-lite plan for SPEC in FORMAT (see `health-chart-backends')."
  (let* ((filled (health-chart--template-program 'vega-lite spec format))
         (scale (or (plist-get spec :scale) health-chart-image-scale))
         (svg (health-chart--command health-chart-vl2svg-command "vl2svg" "vl2svg"))
         (rsvg (lambda (fmt)
                 (list (list :argv svg)
                       (list :argv (append health-chart-rsvg-convert-command
                                           (list "-f" fmt "-z" (format "%s" scale)))))))
         (direct (lambda (custom exe)
                   (list (list :argv (append (health-chart--command custom exe exe)
                                             (when (equal exe "vl2png")
                                               (list "-s" (format "%s" scale))))))))
         (raster (lambda (custom exe fmt)
                   (pcase (if (and (eq health-chart-vega-lite-raster 'auto)
                                   health-chart--vl-canvas-broken)
                              'rsvg-convert
                            health-chart-vega-lite-raster)
                     ('rsvg-convert (list :steps (funcall rsvg fmt)))
                     ('vl2png (list :steps (funcall direct custom exe)))
                     (_ (list :steps (funcall direct custom exe)
                              :fallback (funcall rsvg fmt)))))))
    (append (list :backend 'vega-lite :format format :template (car filled)
                  :program (cdr filled))
            (pcase format
              ('vega-lite (list :steps nil))
              ('svg (list :steps (list (list :argv svg))))
              ('png (funcall raster health-chart-vl2png-command "vl2png" "png"))
              ('pdf (funcall raster health-chart-vl2pdf-command "vl2pdf" "pdf"))
              (_ (signal 'health-chart-backend-error
                         (list (format "vega-lite cannot write %s; use svg, png, pdf or vega-lite" format)
                               :code "unsupported_format")))))))

;; -----------------------------------------------------------------------
;; gnuplot
;; -----------------------------------------------------------------------

(defun health-chart--gp-font (spec scale)
  "The gnuplot font string for SPEC at SCALE."
  (format "%s,%s" (plist-get spec :font)
          (health-chart-template--number (* scale (plist-get spec :font_size)))))

(defun health-chart-gnuplot-preamble (spec format out)
  "Return the gnuplot lines selecting FORMAT's terminal for SPEC, writing OUT."
  (let* ((w (plist-get spec :width)) (h (plist-get spec :height))
         (scale (or (plist-get spec :scale) health-chart-image-scale))
         (bg (plist-get (plist-get spec :colors) :surface))
         (q #'health-chart-template--gp-string))
    (string-join
     (delq nil
           (list
            (format "# health-chart: %s chart, %s, generated from a template" (plist-get spec :kind) format)
            "set encoding utf8"
            (pcase format
              ('svg (format "set terminal svg size %d,%d dynamic noenhanced font %s background %s"
                            w h (funcall q (health-chart--gp-font spec 1)) (funcall q bg)))
              ('png (format "set terminal pngcairo size %d,%d noenhanced font %s fontscale %s linewidth %s pointscale %s background %s"
                            (round (* scale w)) (round (* scale h))
                            (funcall q (health-chart--gp-font spec 1))
                            (health-chart-template--number scale)
                            (health-chart-template--number scale)
                            (health-chart-template--number scale) (funcall q bg)))
              ('pdf (format "set terminal pdfcairo size %sin,%sin noenhanced font %s background %s"
                            (health-chart-template--number (/ w 96.0))
                            (health-chart-template--number (/ h 96.0))
                            (funcall q (health-chart--gp-font spec 0.75)) (funcall q bg)))
              ('text (format "set terminal dumb noenhanced size %d,%d"
                             (plist-get spec :text_width) (plist-get spec :text_height)))
              (_ (signal 'health-chart-backend-error
                         (list (format "gnuplot cannot write %s; use svg, png, pdf or text" format)
                               :code "unsupported_format"))))
            (when (and out (memq format '(png pdf)))
              (format "set output %s" (funcall q (expand-file-name out))))
            "set datafile separator \"\\t\""
            "set datafile columnheaders"
            ""))
     "\n")))

(defun health-chart-gnuplot-explain (spec format &optional out)
  "Return the gnuplot plan for SPEC in FORMAT writing OUT.
The plan has the template, :program and :steps.
PNG and PDF are written by gnuplot itself to OUT (a temporary file when
OUT is nil); SVG and text come back on stdout."
  (let* ((filled (health-chart--template-program 'gnuplot spec format)))
    (list :backend 'gnuplot :format format :template (car filled)
          :program (concat (health-chart-gnuplot-preamble spec format out) (cdr filled)
                           (if (string-suffix-p "\n" (cdr filled)) "" "\n")
                           (if (memq format '(png pdf)) "unset output\n" ""))
          :steps (list (list :argv health-chart-gnuplot-command
                             :writes-file (and (memq format '(png pdf)) t))))))

(defun health-chart-gnuplot-render (spec format out)
  "Render SPEC with gnuplot as FORMAT to OUT, or return the output.
gnuplot writes PNG and PDF itself (to a temporary file when OUT is nil)."
  (cond
   ((not (memq format '(png pdf)))
    (health-chart--render-plan (health-chart-gnuplot-explain spec format out) format out))
   (out
    (let ((plan (health-chart-gnuplot-explain spec format out)))
      (health-chart--pipe (plist-get plan :steps) (plist-get plan :program) nil)
      out))
   (t
    (let ((tmp (make-temp-file "health-chart" nil (alist-get format health-chart-formats))))
      (unwind-protect
          (progn (health-chart-gnuplot-render spec format tmp)
                 (health-chart--read-bytes tmp))
        (delete-file tmp))))))

(defun health-chart-vega-lite-render (spec format out)
  "Render SPEC with Vega-Lite as FORMAT to OUT, or return the output."
  (health-chart--render-plan (health-chart-vega-lite-explain spec format out) format out))

;; -----------------------------------------------------------------------
;; Render and write
;; -----------------------------------------------------------------------

(defun health-chart--render-props (props)
  "PROPS without the render-only ones."
  (health-chart--plist-drop props :backend :format :scale))

(defun health-chart-render-explain (kind data &rest props)
  "The plan `health-chart-render' follows for KIND, DATA and PROPS.  Pure.
A plist: :backend :format :reason, and for template backends :template,
:program (the filled template plus terminal lines) and :steps (each an
:argv run with the previous output on stdin; the first gets :program),
with :fallback steps when PNG/PDF may need rsvg-convert."
  (pcase-let* ((`(,backend ,format ,reason)
                (health-chart-select-backend kind (plist-get props :backend) (plist-get props :format)))
               (plist (health-chart--backend backend)))
    (append (list :backend backend :format format :reason reason)
            (if (plist-get plist :native)
                (list :renderer (plist-get (health-chart--kind kind) (plist-get plist :native)))
              (let ((spec (append (apply #'health-chart-spec kind data (health-chart--render-props props))
                                  (list :scale (or (plist-get props :scale) health-chart-image-scale)))))
                (health-chart--plist-drop (funcall (plist-get plist :explain) spec format
                                                   (plist-get props :out))
                                          :backend :format))))))

(defun health-chart--render-native (backend kind data props)
  "Native BACKEND (text or svg) drawing KIND of DATA under PROPS."
  (let ((data (health-chart-normalize kind data)))
    (apply #'health-chart-validate kind data (health-chart--plist-drop props :format :scale :out))
    (apply (plist-get (health-chart--kind kind) (plist-get (health-chart--backend backend) :native))
           data
           (if (eq backend 'svg)
               (append (when (plist-get props :pixel-width) (list :width (plist-get props :pixel-width)))
                       (when (plist-get props :pixel-height) (list :height (plist-get props :pixel-height)))
                       (health-chart--plist-drop props :backend :format :scale :out :width :height
                                                 :pixel-width :pixel-height))
             (health-chart--plist-drop props :backend :format :scale :out :pixel-width :pixel-height)))))

(defun health-chart-render-string (kind data &rest props)
  "Render KIND of DATA under PROPS; return (BACKEND FORMAT OUTPUT).
OUTPUT is a string (bytes for png and pdf), or nil when there is
nothing to draw.  PROPS' :out writes the output to that file instead,
OUTPUT then being the file name.  When the backend is `auto' and the
chosen one's tools cannot write the format (Vega-Lite PNG with neither
a working vl2png nor rsvg-convert, as on Windows), the next installed
backend of `health-chart-graphic-backends' draws it."
  (condition-case err
      (apply #'health-chart--render-string kind data props)
    (health-chart-backend-error
     (let ((next (and (equal (plist-get (cddr err) :code) "backend_missing")
                      (health-chart--next-backend kind props))))
       (if next
           (apply #'health-chart-render-string kind data :backend next props)
         (signal (car err) (cdr err)))))))

(defun health-chart--next-backend (kind props)
  "The installed backend after the one `auto' chose for KIND under PROPS.
Nil unless PROPS leave the backend to `auto' and set a :format."
  (let ((format (plist-get props :format)))
    (when (and format (eq (or (plist-get props :backend) health-chart-backend) 'auto))
      (let ((tried (car (health-chart-select-backend kind 'auto format))))
        (seq-find (lambda (b)
                    (and (assq b health-chart-backends)
                         (health-chart--supports-p b kind format)
                         (health-chart-backend-available-p b)))
                  (cdr (memq tried health-chart-graphic-backends)))))))

(defun health-chart--render-string (kind data &rest props)
  "`health-chart-render-string' of KIND, DATA and PROPS without the fallback."
  (pcase-let* ((`(,backend ,format ,_reason)
                (health-chart-select-backend kind (plist-get props :backend) (plist-get props :format)))
               (plist (health-chart--backend backend))
               (out (plist-get props :out)))
    (list backend format
          (if (plist-get plist :native)
              (let ((s (health-chart--render-native backend kind data props)))
                (if (and out s) (progn (health-chart--write-bytes (substring-no-properties s) out) out) s))
            (let ((spec (append (apply #'health-chart-spec kind data (health-chart--render-props
                                                                     (health-chart--plist-drop props :out)))
                                (list :scale (or (plist-get props :scale) health-chart-image-scale)))))
              (when (> (length (plist-get spec :rows)) 0)
                (funcall (plist-get plist :render) spec format out)))))))

;;;###autoload
(defun health-chart-render (kind data &rest props)
  "Render DATA as a KIND chart with the selected backend.
With no :format, return an image object where the frame shows images
\(SVG, or PNG when this Emacs lacks SVG) and a text string in a
terminal.  With :format (svg png pdf text vega-lite) return that output
as a string -- raw bytes for png and pdf.  PROPS also take :backend
\(auto vega-lite gnuplot text svg), :scale (PNG pixel ratio) and every
`health-chart-spec' prop.  KIND may be any kind with a template, also
one known only by a file in `health-chart-template-directories'.
Returns nil when there is nothing to draw."
  (if (plist-get props :format)
      (nth 2 (apply #'health-chart-render-string kind data props))
    (let* ((graphic (health-chart--graphic-context-p))
           (format (and graphic (health-chart--image-format))))
      (pcase-let ((`(,_backend ,fmt ,out)
                   (apply #'health-chart-render-string kind data
                          (if format
                              (condition-case nil
                                  (progn (health-chart-select-backend kind (plist-get props :backend) format)
                                         (append (list :format format) props))
                                (health-chart-backend-error props))
                            props))))
        (cond ((null out) nil)
              ((memq fmt '(svg png)) (create-image out fmt t :ascent 'center))
              (t out))))))

(defun health-chart-format-of-file (file)
  "The output format FILE's extension names, or signal."
  (or (car (seq-find (lambda (f) (string-suffix-p (cdr f) (downcase file) t))
                     (append '((vega-lite . ".vl.json") (vega-lite . ".json"))
                             health-chart-formats)))
      (signal 'health-chart-backend-error
              (list (format "cannot tell a format from %s; end it in .svg, .png, .pdf, .txt or .vl.json"
                            (file-name-nondirectory file))
                    :code "unknown_format" :file file))))

;;;###autoload
(defun health-chart-write (kind data file &rest props)
  "Write DATA as a KIND chart to FILE; return FILE.
The format comes from FILE's extension (.svg .png .pdf .txt .vl.json);
PROPS as in `health-chart-render'.  Signals when nothing can be drawn."
  (let* ((file (expand-file-name file))
         (format (health-chart-format-of-file file)))
    (or (nth 2 (apply #'health-chart-render-string kind data
                      (append (list :format format :out file) props)))
        (signal 'health-chart-invalid-data
                (list (format "nothing to draw for %s; check :person and :marker" kind)
                      :code "empty_chart")))))

;; -----------------------------------------------------------------------
;; Health
;; -----------------------------------------------------------------------

(defun health-chart-render-doctor-checks ()
  "Doctor rows: each backend's tools, and every template fills its kind's example."
  (append
   (cl-loop for (name . plist) in health-chart-backends
            unless (plist-get plist :native)
            collect (if (health-chart-backend-available-p name)
                        (list :name (format "backend %s" name) :status 'pass
                              :detail (format "installed; formats %s"
                                              (mapconcat #'symbol-name (plist-get plist :formats) " ")))
                      (list :name (format "backend %s" name) :status 'skip
                            :detail "not installed; charts use the next backend"
                            :remediation (plist-get plist :install))))
   (list (if (health-chart--rsvg-available-p)
             (list :name "rsvg-convert" :status 'pass
                   :detail "PNG/PDF from SVG when node-canvas is missing")
           (list :name "rsvg-convert" :status 'skip
                 :detail "not installed; vega-lite PNG/PDF then needs node-canvas (vl2png), SVG works without it"
                 :remediation "apt install librsvg2-bin, brew install librsvg, or choco install rsvg-convert")))
   (mapcar
    (lambda (tpl)
      (let* ((kind (plist-get tpl :kind))
             (problem
              (condition-case err
                  (let* ((entry (health-chart--kind kind))
                         (example (plist-get (alist-get (plist-get entry :shape) health-chart-shapes)
                                             :example))
                         (spec (health-chart-spec kind example))
                         (plan (funcall (plist-get (health-chart--backend (plist-get tpl :backend)) :explain)
                                        spec (if (eq (plist-get tpl :backend) 'vega-lite) 'vega-lite 'svg))))
                    (when (eq (plist-get tpl :backend) 'vega-lite)
                      (ignore (json-parse-string (plist-get plan :program))))
                    nil)
                (error (error-message-string err)))))
        (list :name (format "template %s/%s" (plist-get tpl :backend) kind)
              :status (if problem 'fail 'pass)
              :detail (or problem (format "fills from the %s example (%s)" kind
                                          (abbreviate-file-name (plist-get tpl :path))))
              :remediation (when problem "fix the template's placeholders (docs/chartspec.md)"))))
    (health-chart-templates))))

(provide 'health-chart-render)
;;; health-chart-render.el ends here
