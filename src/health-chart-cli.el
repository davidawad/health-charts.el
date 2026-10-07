;;; health-chart-cli.el --- bin/health-chart: eas's verbs plus validate and templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The shell door.  `templates' lists the templates and `validate NAME
;; --data FILE' checks bindings with health-chart's own validator
;; (reason code and JSON path); every other verb (describe, example,
;; check, render, export, explain, doctor) is eas's, with this package's
;; templates registered.  Each verb answers the chart/v1 envelope and
;; exits 1 on failure.

;;; Code:

(require 'eas-agent-cli)
(require 'health-chart)

(defun health-chart-cli--null (value)
  "VALUE, or `:null' when it is nil."
  (if (null value) :null value))

(defun health-chart-cli--envelope (ok data &optional reason evidence next)
  "The chart/v1 envelope for OK with DATA, REASON, EVIDENCE and NEXT, as JSON text."
  (concat
   (eas-json-pretty
    (append (list :contract "chart/v1" :ok (if ok t :false) :data (health-chart-cli--null data))
            (and reason (list :reason reason))
            (and evidence (list :evidence evidence))
            (list :next (vconcat next))))))

(defun health-chart-cli--option (argv name)
  "The value after option NAME in ARGV, or nil."
  (cadr (member name argv)))

(defun health-chart-cli-run (argv)
  "Run `health-chart' ARGV; return (EXIT . OUTPUT)."
  (pcase (car argv)
    ("templates"
     (cons 0 (health-chart-cli--envelope
              t (vconcat (mapcar (lambda (row)
                                   (list :name (car row) :group (plist-get (cdr row) :group)
                                         :doc (plist-get (cdr row) :doc)))
                                 (health-chart-list-templates)))
              nil nil '("health-chart describe templates" "health-chart example NAME --raw"))))
    ("validate"
     (let ((name (cadr argv)) (file (health-chart-cli--option argv "--data")))
       (condition-case err
           (progn
             (unless (and name file)
               (signal 'health-chart-error
                       (list "usage: health-chart validate NAME --data BINDINGS.json"
                             :code "usage")))
             (health-chart-validate name (health-chart-read-bindings file))
             (cons 0 (health-chart-cli--envelope
                      t (list :template name :valid t) nil nil
                      (list (format "health-chart render %s --data %s" name file)))))
         (health-chart-error
          (let ((data (health-chart-error-data err)))
            (cons 1 (health-chart-cli--envelope
                     nil nil "INVALID_DATA"
                     (list :code (health-chart-cli--null (plist-get data :code))
                           :path (health-chart-cli--null (plist-get data :path))
                           :index (health-chart-cli--null (plist-get data :index))
                           :field (health-chart-cli--null (plist-get data :field))
                           :message (plist-get data :message))
                     '("health-chart describe templates")))))
         (eas-error
          (cons 1 (health-chart-cli--envelope
                   nil nil "INVALID_INPUT"
                   (list :message (or (plist-get (eas-error-plist err) :message)
                                      (error-message-string err)))
                   '("health-chart describe verbs")))))))
    (_ (eas-agent-cli-run argv))))

(defun health-chart-cli-main ()
  "Entry point for bin/health-chart: run `command-line-args-left' and exit."
  (let* ((argv (if (equal (car command-line-args-left) "--")
                   (cdr command-line-args-left)
                 command-line-args-left))
         (result (health-chart-cli-run argv)))
    (setq command-line-args-left nil)
    (princ (cdr result))
    (kill-emacs (car result))))

(provide 'health-chart-cli)
;;; health-chart-cli.el ends here
