;;; health-chart-batch.el --- JSON command line for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The package for callers outside Emacs.  bin/health-chart runs Emacs
;; in batch mode with
;;
;;   -Q --batch -L DIR -l health-chart-batch -f health-chart-batch-main CMD [ARG...]
;;
;; CMD is one of:
;;
;;   render   [FILE|-]          chart SPEC (JSON) -> the chart, text or SVG
;;   write    SPEC OUT          chart SPEC (file or -) -> OUT, the format
;;                              from its extension (.svg .png .pdf .txt
;;                              .vl.json); prints {"ok":true,"file":OUT}
;;   spec     [FILE|-]          chart SPEC -> the chartspec/v1 JSON
;;   explain  [FILE|-]          chart SPEC -> the plan as JSON (backend,
;;                              template, generated program, argv)
;;   validate [FILE|-]          chart SPEC -> {"ok":true} or the error envelope
;;   pipe     KIND [PROPS]      biomarker JSON on stdin -> KIND chart (text
;;                              unless PROPS, a JSON object, says otherwise)
;;   example  KIND              a ready-to-edit SPEC for KIND, as JSON
;;   kinds                      every kind with its shape and doc, as JSON
;;   describe                   the whole package as JSON
;;   doctor                     health rows as JSON
;;   backends                   rendering backends and whether installed
;;   templates                  every (backend, kind) template and its path
;;   cohorts                    every indicator cohort, as JSON
;;   cohort   NAME [PROPS]      fetch and render cohort NAME (PROPS: "kind"
;;                              scorecard|cohort|staleness, "person",
;;                              "as_of", "backend", ...; text by default)
;;   cohort-explain NAME [PROPS]  the pure plan of `cohort', as JSON
;;
;; A SPEC is a JSON object: {"kind": "timeseries", "data": [...], ...props},
;; props being the keyword arguments of `health-chart-plot' without the
;; colon ("backend": "text", "width": 72, "marker": "ldl_c", "ref": false).
;; "data" is a list of biomarker/v1 measurement objects or a whole
;; biomarker/v1 envelope, so `biomarker ... --format json' output can be
;; dropped in as-is; for the sparkline kind it is a list of numbers.
;;
;; Failures print {"ok":false,"error":{"code","message"}} on stdout and
;; exit 1.

;;; Code:

(require 'json)
(require 'health-chart)

(defconst health-chart-batch--symbol-props '(:backend :format :theme)
  "Props whose JSON string value is a Lisp symbol.")

(defun health-chart-batch--keyword (key)
  "JSON object KEY (a symbol) as a keyword, underscores read as hyphens."
  (intern (concat ":" (replace-regexp-in-string "_" "-" (symbol-name key)))))

(defun health-chart-batch--props (json &optional skip)
  "Plist of chart props from JSON object alist, ignoring keys in SKIP."
  (cl-loop for (k . v) in json
           for key = (health-chart-batch--keyword k)
           ;; null means "not given": the default applies, unlike false
           unless (or (memq k skip) (eq v :null))
           append (list key (if (and (memq key health-chart-batch--symbol-props) (stringp v))
                                (intern (downcase v))
                              v))))

(defun health-chart-batch-spec (json)
  "Chart spec plist from JSON (an alist from `json-parse-string')."
  (unless (and (consp json) (consp (car json)))
    (signal 'health-chart-error (list "a spec is a JSON object: {\"kind\": ..., \"data\": [...]}"
                                      :code "bad_request")))
  (let ((kind-name (alist-get 'kind json)))
    (unless (stringp kind-name)
      (signal 'health-chart-error
              (list "spec needs \"kind\" as a string; run `health-chart kinds'"
                    :code "bad_request")))
    (append (list :kind (intern kind-name) :data (alist-get 'data json))
            (health-chart-batch--props json '(kind data)))))

(defun health-chart-batch--parse (text)
  "Parse JSON TEXT as every batch command does."
  (json-parse-string text :object-type 'alist :array-type 'list
                     :null-object :null :false-object nil))

(defun health-chart-batch--read-text (file)
  "The contents of FILE (\"-\" or nil = stdin)."
  (with-temp-buffer
    (if (or (null file) (equal file "-"))
        ;; Not `insert-file-contents' on /dev/stdin: Emacs 29.1 rejects a
        ;; pipe there.  In batch mode `read-from-minibuffer' reads one
        ;; stdin line and signals at EOF.
        (let (line)
          (while (setq line (ignore-errors (read-from-minibuffer "")))
            (insert line "\n")))
      (insert-file-contents file))
    (buffer-string)))

(defun health-chart-batch--json (value)
  "Print VALUE as JSON on stdout."
  (princ (json-encode value))
  (terpri))

(defun health-chart-batch--example (kind)
  "A SPEC for KIND built from its shape's example, as a JSON-able alist."
  (let* ((d (health-chart-describe-kind kind))
         (ex (plist-get d :example)))
    `((kind . ,(symbol-name kind))
      (data . ,(apply #'vector
                      (if (eq (plist-get d :shape) 'measurements)
                          (mapcar #'health-chart-source-to-json ex)
                        ex)))
      ,@(pcase kind
          ((or 'timeseries 'compare) '((marker . "ldl_c")))
          ('panel '((marker . ["ldl_c" "apob" "glucose" "crp"]))))
      ,@(unless (memq kind '(compare sparkline)) '((person . "alex")))
      (backend . "text"))))

(defun health-chart-batch--jsonable (v)
  "V with plists as objects and other lists as arrays, for `json-encode'."
  (cond
   ((and (proper-list-p v) (keywordp (car v)) (cl-evenp (length v))
         (cl-loop for (k) on v by #'cddr always (keywordp k)))
    (cl-loop for (k x) on v by #'cddr
             collect (cons (intern (substring (symbol-name k) 1))
                           (health-chart-batch--jsonable x))))
   ((proper-list-p v) (if v (apply #'vector (mapcar #'health-chart-batch--jsonable v)) v))
   ((consp v) (vector (health-chart-batch--jsonable (car v)) (health-chart-batch--jsonable (cdr v))))
   (t v)))

(defun health-chart-batch--cohort-props (json)
  "Cohort command props from JSON (a parsed PROPS object or nil)."
  (unless (or (null json) (and (consp json) (consp (car json))))
    (signal 'health-chart-error
            (list "cohort PROPS must be a JSON object, e.g. '{\"kind\":\"staleness\"}'"
                  :code "bad_request")))
  (let ((props (health-chart-batch--props json)))
    (when (stringp (plist-get props :kind))
      (setq props (plist-put props :kind (intern (plist-get props :kind)))))
    (append props (unless (plist-member props :backend) '(:backend text)))))

(defun health-chart-batch--cohort-args (args)
  "The (NAME . PROPS) of a cohort command's ARGS, or signal."
  (unless (car args)
    (signal 'health-chart-error
            (list "cohort needs a NAME; run `health-chart cohorts'" :code "bad_request")))
  (cons (intern (car args))
        (health-chart-batch--cohort-props
         (when (cadr args) (health-chart-batch--parse (cadr args))))))

(defun health-chart-batch--error-code (err)
  "Stable code for ERR: its :code, else derived from its symbol."
  (or (plist-get (cddr err) :code)
      (pcase (car err)
        ('json-parse-error "bad_json")
        ('json-end-of-file "bad_json")
        ('file-missing "file_missing")
        (_ "error"))))

(defun health-chart-batch--print-chart (out)
  "Print rendered chart OUT, or nothing-to-draw text, on stdout."
  (princ (if (stringp out) (substring-no-properties out) health-chart-empty-text))
  (terpri))

(defun health-chart-batch-run (cmd &rest args)
  "Run batch command CMD with ARGS; return the process exit status."
  (condition-case err
      (let ((arg (car args)))
        (pcase cmd
          ("render"
           (health-chart-batch--print-chart
            (health-chart-plot-spec
             (health-chart-batch-spec (health-chart-batch--parse (health-chart-batch--read-text arg))))))
          ("explain"
           (let ((spec (health-chart-batch-spec
                        (health-chart-batch--parse (health-chart-batch--read-text arg)))))
             (health-chart-batch--json
              (health-chart-batch--jsonable
               (apply #'health-chart-explain (plist-get spec :kind) (plist-get spec :data)
                      (health-chart--plist-drop spec :kind :data))))))
          ("spec"
           (let ((spec (health-chart-batch-spec
                        (health-chart-batch--parse (health-chart-batch--read-text arg)))))
             (princ (health-chart-spec-to-json
                     (apply #'health-chart-spec (plist-get spec :kind) (plist-get spec :data)
                            (health-chart--plist-drop spec :kind :data))
                     t))
             (terpri)))
          ("write"
           (unless (cadr args)
             (signal 'health-chart-error
                     (list "write needs SPEC and OUT, e.g. `health-chart write spec.json chart.png'"
                           :code "bad_request")))
           (let ((spec (health-chart-batch-spec
                        (health-chart-batch--parse (health-chart-batch--read-text arg)))))
             (health-chart-batch--json
              `((ok . t)
                (file . ,(apply #'health-chart-write (plist-get spec :kind) (plist-get spec :data)
                                (cadr args) (health-chart--plist-drop spec :kind :data)))))))
          ("backends"
           (health-chart-batch--json
            (apply #'vector
                   (mapcar (lambda (b)
                             `((backend . ,(symbol-name (car b)))
                               (available . ,(if (health-chart-backend-available-p (car b)) t :json-false))
                               (formats . ,(apply #'vector (mapcar #'symbol-name (plist-get (cdr b) :formats))))
                               (doc . ,(plist-get (cdr b) :doc))))
                           health-chart-backends))))
          ("templates"
           (health-chart-batch--json
            (apply #'vector
                   (mapcar (lambda (tpl)
                             `((backend . ,(symbol-name (plist-get tpl :backend)))
                               (kind . ,(symbol-name (plist-get tpl :kind)))
                               (path . ,(plist-get tpl :path))
                               (source . ,(symbol-name (plist-get tpl :source)))))
                           (health-chart-templates)))))
          ("validate"
           (let ((spec (health-chart-batch-spec
                        (health-chart-batch--parse (health-chart-batch--read-text arg)))))
             (apply #'health-chart-validate (plist-get spec :kind) (plist-get spec :data)
                    (health-chart--plist-drop spec :kind :data))
             (health-chart-batch--json '((ok . t)))))
          ("pipe"
           (unless arg
             (signal 'health-chart-error
                     (list "pipe needs a KIND, e.g. `biomarker trend ... | health-chart pipe timeseries'"
                           :code "bad_request")))
           (let* ((json (when (cadr args) (health-chart-batch--parse (cadr args))))
                  (props (progn
                           (unless (or (null json) (and (consp json) (consp (car json))))
                             (signal 'health-chart-error
                                     (list "pipe PROPS must be a JSON object, e.g. '{\"width\":60}'"
                                           :code "bad_request")))
                           (health-chart-batch--props json))))
             (health-chart-batch--print-chart
              (apply #'health-chart-plot (intern arg)
                     (health-chart-batch--parse (health-chart-batch--read-text "-"))
                     (append props (unless (plist-member props :backend) '(:backend text)))))))
          ("example"
           (health-chart-batch--json (health-chart-batch--example (intern (or arg "timeseries")))))
          ("kinds" (health-chart-batch--json (plist-get (health-chart-describe) :kinds)))
          ("describe" (health-chart-batch--json (health-chart-describe)))
          ("doctor" (health-chart-batch--json (apply #'vector (health-chart-doctor-checks))))
          ("cohorts" (health-chart-batch--json (plist-get (health-chart-describe) :cohorts)))
          ("cohort"
           (let ((call (health-chart-batch--cohort-args args)))
             (health-chart-batch--print-chart (apply #'health-chart-cohort-plot (car call) (cdr call)))))
          ("cohort-explain"
           (let ((call (health-chart-batch--cohort-args args)))
             (health-chart-batch--json
              (health-chart-batch--jsonable
               (apply #'health-chart-cohort-plot-explain (car call) (cdr call))))))
          (_ (signal 'health-chart-error
                     (list (format "unknown command %S; use render, write, spec, explain, validate, pipe, example, kinds, \
describe, doctor, backends, templates, cohorts, cohort or cohort-explain" cmd)
                           :code "bad_request"))))
        0)
    (error
     (health-chart-batch--json
      `((ok . :json-false)
        (error . ((code . ,(health-chart-batch--error-code err))
                  (message . ,(if (plist-get (cddr err) :code) (cadr err)
                                (error-message-string err)))))))
     1)))

(defun health-chart-batch-main ()
  "Entry point for `emacs --batch -f health-chart-batch-main CMD [ARG...]'."
  (let ((args command-line-args-left))
    (setq command-line-args-left nil)
    (kill-emacs (apply #'health-chart-batch-run (or (car args) "describe") (cdr args)))))

(provide 'health-chart-batch)
;;; health-chart-batch.el ends here
