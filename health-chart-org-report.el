;;; health-chart-org-report.el --- Org report templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Report templates: list, find and stamp them into a new report.

;;; Code:

(require 'health-chart-org-base)

;; -----------------------------------------------------------------------
;; Report templates
;; -----------------------------------------------------------------------

(defun health-chart-org-template-directories ()
  "Report template directories in search order: the user's, then the bundled."
  (append (mapcar #'expand-file-name health-chart-org-template-directories)
          (list health-chart-org-bundled-template-directory)))

(defun health-chart-org--template-title (file)
  "The #+TITLE of template FILE, placeholders and all, or nil."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file nil 0 2000))
    (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
      (string-trim (match-string 1)))))

(defun health-chart-org-template-list ()
  "Every report template as (:name :path :source :title), first match wins.
:source is user or bundled."
  (let (found)
    (dolist (dir (health-chart-org-template-directories))
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.org\\'"))
          (let ((name (file-name-base file)))
            (unless (assoc name found)
              (push (cons name (list :name name :path file
                                     :source (if (equal dir health-chart-org-bundled-template-directory)
                                                 'bundled 'user)
                                     :title (health-chart-org--template-title file)))
                    found))))))
    (mapcar #'cdr (sort found (lambda (a b) (string< (car a) (car b)))))))

;;;###autoload
(defun health-chart-org-templates ()
  "List the report templates; interactively, show them in a buffer."
  (interactive)
  (let ((templates (health-chart-org-template-list)))
    (when (called-interactively-p 'interactive)
      (with-current-buffer (get-buffer-create "*health-chart org templates*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (dolist (tpl templates)
            (insert (format "%-22s %-8s %s\n  %s\n" (plist-get tpl :name) (plist-get tpl :source)
                            (or (plist-get tpl :title) "")
                            (abbreviate-file-name (plist-get tpl :path))))))
        (special-mode)
        (pop-to-buffer (current-buffer))))
    templates))

(defun health-chart-org-template-find (name)
  "The file of report template NAME, or signal."
  (or (plist-get (seq-find (lambda (tpl) (equal (plist-get tpl :name) name))
                           (health-chart-org-template-list))
                 :path)
      (signal 'health-chart-org-error
              (list (format "no report template %S; use one of %s (or add NAME.org to `health-chart-org-template-directories')"
                            name (mapconcat (lambda (tpl) (plist-get tpl :name))
                                            (health-chart-org-template-list) " "))
                    :code "unknown_template" :template name))))

(defun health-chart-org--year-before (date)
  "DATE one year earlier (Feb 29 becomes Feb 28)."
  (let ((y (string-to-number (substring date 0 4))) (md (substring date 4)))
    (format "%04d%s" (1- y) (if (equal md "-02-29") "-02-28" md))))

(defun health-chart-org-context (&rest args)
  "The placeholder context of a report from ARGS.
ARGS: :person (default `health-chart-default-person'), :date (default
today), :until (default :date), :since (default a year before
:until).  Adds :period (\"SINCE – UNTIL\") and :year (of :until)."
  (let* ((date (or (plist-get args :date) (format-time-string "%Y-%m-%d")))
         (until (or (plist-get args :until) date))
         (since (or (plist-get args :since) (health-chart-org--year-before until))))
    (dolist (d (list date since until))
      (unless (health-chart-date-p d)
        (signal 'health-chart-org-error
                (list (format "report dates must look like 2025-01-31, got %S" d)
                      :code "invalid_param"))))
    (list :person (or (plist-get args :person) health-chart-default-person "")
          :date date :since since :until until
          :period (format "%s – %s" since until)
          :year (substring until 0 4))))

(defun health-chart-org--template-file (template)
  "TEMPLATE's file: itself when absolute, else found by name."
  (if (file-name-absolute-p template) template (health-chart-org-template-find template)))

(defun health-chart-org-stamp (template context)
  "Report TEMPLATE (a name or file) filled from CONTEXT; return the text.
Pure apart from reading the template.  CONTEXT is a plist from
`health-chart-org-context'; an unknown placeholder signals, naming the
template file and line."
  (let ((file (health-chart-org--template-file template)))
    (health-chart-template-fill (health-chart-template-read file) context 'text file)))

(defun health-chart-org-new-report-explain (template output &rest args)
  "The plan of `health-chart-org-new-report' for TEMPLATE, OUTPUT, ARGS.  Pure.
A plist: :template (its file) :output :context :assets :blocks (each
block's explain plan, in document order)."
  (let* ((context (apply #'health-chart-org-context args))
         (output (expand-file-name output))
         (text (health-chart-org-stamp template context))
         (blocks nil) (start 0))
    (while (string-match "^[ \t]*#\\+BEGIN:[ \t]+\\(health-[a-z-]+\\)\\(.*\\)$" text start)
      (let ((name (match-string 1 text)) (raw (match-string 2 text)))
        (setq start (match-end 0))
        (when (assoc name health-chart-org-blocks)
          (push (health-chart-org-explain name (car (read-from-string (concat "(" raw ")"))) output)
                blocks))))
    (list :template (health-chart-org--template-file template) :output output :context context
          :assets (health-chart-org-asset-dir output) :blocks (nreverse blocks))))

;;;###autoload
(defun health-chart-org-new-report (template output &rest args)
  "Stamp report TEMPLATE into OUTPUT, refresh its blocks, open it; return OUTPUT.
ARGS: :person :date :since :until (see `health-chart-org-context').
Interactively, prompts for each and confirms before overwriting an
existing OUTPUT.  See `health-chart-org-new-report-explain'."
  (interactive
   (let* ((tpl (completing-read "Report template: "
                                (mapcar (lambda (tpl) (plist-get tpl :name))
                                        (health-chart-org-template-list))
                                nil t))
          (person (read-string "Person: " health-chart-default-person))
          (until (read-string "Period ends: " (format-time-string "%Y-%m-%d")))
          (since (read-string "Period starts: " (health-chart-org--year-before until)))
          (out (read-file-name "Write report to: " nil nil nil
                               (format "%s-%s-%s.org" tpl (health-chart-org--slug person) until))))
     (when (and (file-exists-p out)
                (not (y-or-n-p (format "%s exists; overwrite? " out))))
       (user-error "Not overwriting %s" out))
     (list tpl out :person person :since since :until until)))
  (let* ((output (expand-file-name output))
         (text (health-chart-org-stamp template (apply #'health-chart-org-context args))))
    (make-directory (file-name-directory output) t)
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region text nil output nil 'silent))
    (with-current-buffer (find-file-noselect output)
      (let ((coding-system-for-read 'utf-8-unix))
        (revert-buffer t t t))
      ;; blocks insert non-ASCII glyphs; never prompt for a coding on save
      (set-buffer-file-coding-system 'utf-8-unix)
      (health-chart-org-update)
      (save-buffer)
      (unless noninteractive (pop-to-buffer-same-window (current-buffer))))
    output))

(provide 'health-chart-org-report)
;;; health-chart-org-report.el ends here
