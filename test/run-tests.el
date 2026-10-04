;;; run-tests.el --- Load every test file and run the suite -*- lexical-binding: t; -*-

;;; Commentary:

;; The one entry point for the suite, used by `make test' and by CI
;; where make is absent (native Windows):
;;
;;   emacs -Q --batch -l test/run-tests.el
;;
;; It puts the package and test directories on `load-path' itself, so
;; it runs from any directory.  An optional ERT selector (a regexp)
;; comes from the first command-line argument after the file or from
;; HEALTH_CHART_TEST_SELECTOR.  Tests needing gnuplot, Vega-Lite or
;; genetics.el skip where those are absent.

;;; Code:

(require 'ert)

(let* ((test-dir (file-name-directory (or load-file-name buffer-file-name)))
       (root (expand-file-name ".." test-dir)))
  (add-to-list 'load-path root)
  (add-to-list 'load-path test-dir)
  (dolist (file (directory-files test-dir t "-test\\.el\\'"))
    (load file nil t)))

(let ((selector (or (pop command-line-args-left)
                    (getenv "HEALTH_CHART_TEST_SELECTOR"))))
  (ert-run-tests-batch-and-exit (if (member selector '(nil "")) t selector)))

;;; run-tests.el ends here
