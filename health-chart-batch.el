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
;;   explain  [FILE|-]          chart SPEC -> the plan as JSON
;;   validate [FILE|-]          chart SPEC -> {"ok":true} or the error envelope
;;   pipe     KIND [PROPS]      biomarker JSON on stdin -> KIND chart (text
;;                              unless PROPS, a JSON object, says otherwise)
;;   example  KIND              a ready-to-edit SPEC for KIND, as JSON
;;   kinds                      every kind with its shape and doc, as JSON
;;   describe                   the whole package as JSON
;;   doctor                     health rows as JSON
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

(defconst health-chart-batch--symbol-props '(:backend)
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
              (apply #'health-chart-explain (plist-get spec :kind) (plist-get spec :data)
                     (health-chart--plist-drop spec :kind :data)))))
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
          (_ (signal 'health-chart-error
                     (list (format "unknown command %S; use render, explain, validate, pipe, example, kinds, describe or doctor" cmd)
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
