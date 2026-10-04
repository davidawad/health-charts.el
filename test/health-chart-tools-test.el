;;; health-chart-tools-test.el --- Finding and running the external tools -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Tests of health-chart-tools.el.

;;; Code:

(require 'health-chart-test-helpers)

(defun health-chart-backend-test--fake-tool (dir name)
  "Write an executable NAME in DIR printing \"ok\"; return NAME.
On Windows it is a .cmd file, as npm's shims are."
  (if (eq system-type 'windows-nt)
      (health-chart-backend-test--write (expand-file-name (concat name ".cmd") dir)
                                        "@echo off\r\necho ok\r\n")
    (let ((file (expand-file-name name dir)))
      (health-chart-backend-test--write file "#!/bin/sh\necho ok\n")
      (set-file-modes file #o755)))
  name)

(ert-deftest health-chart-backend-test-tools-found-in-tool-directories ()
  (let* ((dir (make-temp-file "hc-tools" t))
         (name (health-chart-backend-test--fake-tool dir "hc-fake-tool"))
         (health-chart-tool-directories nil))
    (unwind-protect
        (progn
          (should-not (health-chart-executable name))
          (let ((err (should-error (health-chart--run (list name) "")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_missing")))
          (let ((health-chart-tool-directories (list dir)))
            (should (file-equal-p (file-name-directory (health-chart-executable name)) dir))
            ;; run by its resolved name, without a shell; CRLF read as LF
            (should (equal (health-chart--run (list name) "") "ok\n"))
            (let ((health-chart-gnuplot-command (list name)))
              (should (health-chart-gnuplot-available-p)))))
      (delete-directory dir t))))

;; gnuplot on Windows exits 0 after a script error, printing nothing
(ert-deftest health-chart-backend-test-empty-output-is-a-failure ()
  (let* ((dir (make-temp-file "hc-tools" t))
         (health-chart-tool-directories (list dir))
         (name "hc-silent"))
    (unwind-protect
        (progn
          ;; exits at once, never reading stdin
          (if (eq system-type 'windows-nt)
              (health-chart-backend-test--write (expand-file-name (concat name ".cmd") dir)
                                                "@echo off\r\necho oops 1>&2\r\n")
            (let ((file (expand-file-name name dir)))
              (health-chart-backend-test--write file "#!/bin/sh\necho oops >&2\n")
              (set-file-modes file #o755)))
          (let ((err (should-error (health-chart--run (list name) "plot x")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_failed"))
            (should (string-match-p "wrote no output: oops" (cadr err))))
          ;; a tool writing its own file owes nothing on stdout
          (should (equal (health-chart--run (list name) "plot x" nil t) "")))
      (delete-directory dir t))))

(ert-deftest health-chart-backend-test-tools-get-stdin-and-time-out ()
  (skip-unless (not (eq system-type 'windows-nt)))
  (let* ((dir (make-temp-file "hc-tools" t))
         (health-chart-tool-directories (list dir))
         (health-chart-render-timeout 1))
    (unwind-protect
        (progn
          (dolist (tool '(("hc-cat" . "#!/bin/sh\ncat\n")
                          ("hc-fail" . "#!/bin/sh\necho 'bad input ✗' >&2\nexit 3\n")
                          ("hc-hang" . "#!/bin/sh\nexec sleep 30\n")))
            (let ((file (expand-file-name (car tool) dir)))
              (health-chart-backend-test--write file (cdr tool))
              (set-file-modes file #o755)))
          (let ((big (concat (make-string 200000 ?x) "ε\n")))
            (should (equal (health-chart--run '("hc-cat") big) big)))
          (should (equal (health-chart--run '("hc-cat") "\211PNG" t) "\211PNG"))
          (let ((err (should-error (health-chart--run '("hc-fail") "")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_failed"))
            (should (equal (plist-get (cddr err) :exit) 3))
            (should (string-match-p "bad input ✗" (cadr err))))
          (let* ((start (float-time))
                 (err (should-error (health-chart--run '("hc-hang") "")
                                    :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_timeout"))
            (should (< (- (float-time) start) 10))))
      (delete-directory dir t))))

(ert-deftest health-chart-backend-test-png-without-rsvg-says-svg-works ()
  (health-chart-test-env
    (let* ((dir (make-temp-file "hc-tools" t))
           (health-chart-tool-directories (list dir))
           (health-chart-vl2svg-command
            (list (health-chart-backend-test--fake-tool dir "hc-fake-vl2svg")))
           (health-chart-vl2png-command '("hc-no-such-vl2png"))
           (health-chart-rsvg-convert-command '("hc-no-such-rsvg-convert"))
           (health-chart-vega-lite-raster 'auto)
           (health-chart--vl-canvas-broken nil))
      (unwind-protect
          (let ((err (should-error (health-chart-render 'bullet (health-chart-backend-test-sample)
                                                        :backend 'vega-lite :format 'png
                                                        :person "alex")
                                   :type 'health-chart-backend-error)))
            (should (equal (plist-get (cddr err) :code) "backend_missing"))
            (should (string-match-p "hc-no-such-vl2png" (cadr err)))
            (should (string-match-p "write SVG" (cadr err)))
            (should-not health-chart--vl-canvas-broken))
        (delete-directory dir t)))))

(provide 'health-chart-tools-test)
;;; health-chart-tools-test.el ends here
