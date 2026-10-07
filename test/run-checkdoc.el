;;; run-checkdoc.el --- Checkdoc every file named on the command line -*- lexical-binding: t; -*-

;;; Commentary:

;;   emacs -Q --batch -L src -l test/run-checkdoc.el src/*.el
;;
;; Exits 1 when checkdoc reports anything.

;;; Code:

(require 'checkdoc)

(let ((failed nil)
      (checkdoc-diagnostic-buffer "*checkdoc*"))
  (dolist (file command-line-args-left)
    (unless (string-match-p "-test\\.el\\'" file)
      (with-current-buffer (find-file-noselect file)
        (checkdoc-current-buffer t)
        (when-let* ((buffer (get-buffer checkdoc-diagnostic-buffer)))
          (with-current-buffer buffer
            (when (> (buffer-size) 0)
              (setq failed t)
              (princ (buffer-string))
              (let ((inhibit-read-only t)) (erase-buffer))))))))
  (setq command-line-args-left nil)
  (kill-emacs (if failed 1 0)))

;;; run-checkdoc.el ends here
