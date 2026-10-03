;;; run-package-lint.el --- package-lint every file named on the command line -*- lexical-binding: t; -*-

;;; Commentary:

;; Used by `make lint'; exits 1 on any finding but two deliberate
;; exceptions, both the user-facing name `health-charts': the
;; customization group (M-x customize-group RET health-charts) and the
;; dashboard command (M-x health-charts, an alias of
;; `health-chart-dashboard').  package-lint reads that name as off-prefix
;; for the `health-chart' package.  Every other finding fails.

;;; Code:

(require 'package-lint)
(require 'seq)
(require 'subr-x)

(defconst run-package-lint-allowed
  '("\"health-charts\" doesn't start with package's prefix \"health-chart\""
    "Aliases should start with the package's prefix \"health-chart\"")
  "Findings accepted on purpose; see the Commentary.")

(setq package-lint-main-file "health-chart.el")
(let (problems)
  (dolist (file command-line-args-left)
    (with-current-buffer (find-file-noselect file)
      (dolist (finding (package-lint-buffer))
        (pcase-let ((`(,line ,col ,type ,message) finding))
          (unless (and (string-match-p "(def\\(group\\|alias\\) '?health-charts\\_>"
                                       (save-excursion (goto-char (point-min))
                                                       (forward-line (1- line))
                                                       (buffer-substring (point) (line-end-position))))
                       (seq-some (lambda (ok) (string-prefix-p ok message))
                                 run-package-lint-allowed))
            (push (format "%s:%d:%d: %s: %s" file line col type message) problems))))))
  (setq command-line-args-left nil)
  (when problems
    (princ (string-join (nreverse problems) "\n")) (terpri)
    (kill-emacs 1)))

;;; run-package-lint.el ends here
