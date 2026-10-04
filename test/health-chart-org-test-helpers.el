;;; health-chart-org-test-helpers.el --- Shared fixtures for the Org report tests -*- lexical-binding: t; -*-

;;; Commentary:

;; The sample panel as a fake source in a temporary directory, and a
;; helper refreshing every health block of an Org text.  Synthetic data
;; only.

;;; Code:

(require 'health-chart-test-helpers)
(require 'health-chart-org)

(defconst health-chart-org-test--sample
  (expand-file-name "../examples/sample-panel.json" health-chart-test-dir)
  "The synthetic sample panel.")

(defun health-chart-org-test-sample ()
  "The sample panel as canonical measurements."
  (health-chart-source-parse
   (with-temp-buffer
     (let ((coding-system-for-read 'utf-8-unix))
       (insert-file-contents health-chart-org-test--sample))
     (buffer-string))))

(defvar health-chart-org-test-calls nil
  "Source calls made inside `health-chart-org-test-env'.")

(defvar health-chart-org-test-real-genetics nil
  "Non-nil lets `health-chart-org-test-env' see a loaded genetics.el.
Otherwise genetics.el is hidden, so golden output does not depend on
whether another test loaded it into the same Emacs.")

(defconst health-chart-org-test-genetics-functions
  '(org-dblock-write:genetics-summary org-dblock-write:genetics-hits
    org-dblock-write:genetics-apoe genetics-org-kit genetics-kit-resolve)
  "The genetics.el entry points health-charts calls.")

(defmacro health-chart-org-test-hide-genetics (&rest body)
  "Run BODY with genetics.el's entry points unbound, unless real genetics is wanted."
  (declare (indent 0) (debug t))
  `(let ((saved (mapcar (lambda (f) (cons f (and (fboundp f) (symbol-function f))))
                        (unless health-chart-org-test-real-genetics
                          health-chart-org-test-genetics-functions))))
     (unwind-protect
         (progn (dolist (s saved) (fmakunbound (car s))) ,@body)
       (dolist (s saved) (when (cdr s) (fset (car s) (cdr s)))))))

(defmacro health-chart-org-test-env (&rest body)
  "Run BODY in a temporary directory with the sample panel as the source.
`health-chart-org-test-calls' collects every source call.  genetics.el
is hidden unless `health-chart-org-test-real-genetics' is non-nil."
  (declare (indent 0) (debug t))
  `(health-chart-org-test-hide-genetics
    (health-chart-test-env
     (let* ((dir (make-temp-file "hc-org" t))
            (default-directory (file-name-as-directory dir))
            (sample (health-chart-org-test-sample))
            (health-chart-org-test-calls nil)
            (health-chart-source-function
             (lambda (command &rest args)
               (push (cons command args) health-chart-org-test-calls)
               (let ((health-chart-source-static-data sample))
                 (apply #'health-chart-source-static command args))))
            (health-chart-org-template-directories nil)
            (health-chart-org-image-format 'svg)
            (health-chart-org-asset-directory "%s-assets"))
       (ignore health-chart-org-test-calls)
       (unwind-protect (progn ,@body)
         (delete-directory dir t))))))

(defun health-chart-org-test-update (text)
  "TEXT as an Org file in the current directory, every health block refreshed."
  (let ((file (expand-file-name "report.org")))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file file (insert text)))
    (with-current-buffer (let ((coding-system-for-read 'utf-8-unix))
                           (find-file-noselect file))
      (unwind-protect
          (progn (health-chart-org-update)
                 (buffer-substring-no-properties (point-min) (point-max)))
        (set-buffer-modified-p nil)
        (kill-buffer)))))

(provide 'health-chart-org-test-helpers)
;;; health-chart-org-test-helpers.el ends here
