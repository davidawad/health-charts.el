;;; run-checkdoc.el --- checkdoc every file named on the command line -*- lexical-binding: t; -*-

;;; Commentary:

;; Used by `make checkdoc'; exits 1 on any warning.

;;; Code:

;; batch checkdoc over every health-chart file; exit 1 on any warning
(require 'checkdoc)
(require 'seq)
(require 'subr-x)
(setq checkdoc-arguments-in-order-flag nil)
(dolist (f command-line-args-left)
  (with-current-buffer (find-file-noselect f)
    (let ((checkdoc-autofix-flag 'never)) (checkdoc-current-buffer t))))
(setq command-line-args-left nil)
(let ((problems (seq-filter (lambda (line) (string-match-p ":[0-9]+: " line))
                           (split-string (with-current-buffer (get-buffer-create "*Style Warnings*")
                                           (buffer-string))
                                         "\n"))))
  (when problems
    (princ (string-join problems "\n")) (terpri) (kill-emacs 1)))
;;; run-checkdoc.el ends here
