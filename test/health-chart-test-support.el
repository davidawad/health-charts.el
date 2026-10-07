;;; health-chart-test-support.el --- golden helper and template walker -*- lexical-binding: t; -*-

;;; Commentary:

;; Goldens of every template drawn by eas live in test/golden/text/ and
;; test/golden/svg/.  Set HEALTH_CHART_UPDATE_GOLDEN=1 (or `make
;; goldens') to rewrite them, then review the diff.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'health-chart)

(defconst health-chart-test-root
  (file-name-directory
   (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))
  "The health-chart repository root.")

(defun health-chart-test-golden (kind name actual)
  "Compare string ACTUAL with golden NAME under test/golden/KIND/."
  (let ((file (expand-file-name name (expand-file-name (concat "test/golden/" kind)
                                                       health-chart-test-root))))
    (if (or (getenv "HEALTH_CHART_UPDATE_GOLDEN") (not (file-exists-p file)))
        (progn
          (make-directory (file-name-directory file) t)
          (with-temp-file file
            (set-buffer-file-coding-system 'utf-8-unix)
            (insert actual))
          (unless (getenv "HEALTH_CHART_UPDATE_GOLDEN")
            (ert-fail (format "Golden %s was missing and has been written; review and rerun"
                              name))))
      (should (equal (with-temp-buffer
                       (set-buffer-multibyte t)
                       (let ((coding-system-for-read 'utf-8-unix))
                         (insert-file-contents file))
                       (buffer-string))
                     actual)))))

(defun health-chart-test-should-code (code path thunk)
  "Assert THUNK signals `health-chart-invalid-data' with CODE at PATH; return the plist."
  (let* ((err (should-error (funcall thunk) :type 'health-chart-invalid-data))
         (data (health-chart-error-data err)))
    (should (equal (plist-get data :code) code))
    (when path (should (equal (plist-get data :path) path)))
    data))

(provide 'health-chart-test-support)
;;; health-chart-test-support.el ends here
