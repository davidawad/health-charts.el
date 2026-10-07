;;; health-chart-core.el --- Errors and template lookup for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; health-chart draws only data its caller supplies.  Every failure is a
;; typed error whose data is (MESSAGE :code CODE :path PATH :index INDEX
;; :field FIELD): CODE is a stable reason, PATH a JSON path such as
;; "data[3].value", INDEX the offending row (nil when the whole value is
;; wrong) and FIELD the offending field.  `health-chart-error-data'
;; turns the error into a plist.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eas)
(require 'health-chart-eas)

(define-error 'health-chart-error "health-chart error")
(define-error 'health-chart-unknown-template "Unknown health-chart template" 'health-chart-error)
(define-error 'health-chart-invalid-data "Invalid health-chart data" 'health-chart-error)
(define-error 'health-chart-backend-error "health-chart backend error" 'health-chart-error)

(defun health-chart--invalid (code path index field format-string &rest args)
  "Signal `health-chart-invalid-data' with CODE for PATH, INDEX and FIELD.
The message is FORMAT-STRING applied to ARGS."
  (signal 'health-chart-invalid-data
          (list (apply #'format format-string args)
                :code code :path path :index index :field field)))

(defun health-chart-error-data (err)
  "ERR, a `health-chart-error' condition, as a plist.
The keys are :message, :code, :path, :index and :field."
  (let ((data (cdr err)))
    (append (list :message (if (stringp (car data)) (car data) (error-message-string err)))
            (if (stringp (car data)) (cdr data) nil))))

;;; Templates

(defconst health-chart-namespace "health"
  "The eas namespace of health-chart's templates.")

(defun health-chart--qualify (name)
  "The eas template name for NAME, a string or symbol.
NAME may carry the namespace or not."
  (let ((name (if (symbolp name) (symbol-name name) name)))
    (if (string-prefix-p (concat health-chart-namespace "/") name)
        name
      (concat health-chart-namespace "/" name))))

(defun health-chart--short (qualified)
  "QUALIFIED eas template name without the namespace."
  (string-remove-prefix (concat health-chart-namespace "/") qualified))

(defun health-chart-template-names ()
  "Every health-chart template name (without the namespace), sorted."
  (sort (cl-loop for name in (eas-template-names)
                 when (string-prefix-p (concat health-chart-namespace "/") name)
                 collect (health-chart--short name))
        #'string<))

(defun health-chart--template (name)
  "The eas template record for NAME, else signal `health-chart-unknown-template'."
  (let ((qualified (health-chart--qualify name)))
    (if (member qualified (eas-template-names))
        (eas-template-get qualified)
      (signal 'health-chart-unknown-template
              (list (format "No health-chart template %S; templates: %s" name
                            (string-join (health-chart-template-names) ", "))
                    :code "unknown_template" :path nil :index nil :field nil)))))

(provide 'health-chart-core)
;;; health-chart-core.el ends here
