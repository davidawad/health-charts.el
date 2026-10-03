;;; health-chart-dashboard-test.el --- The health-charts dashboard -*- lexical-binding: t; -*-

;;; Code:

(require 'health-chart-test-helpers)

(defmacro health-chart-dashboard-test--with (&rest body)
  "Run BODY in a fresh dashboard over the static example source."
  (declare (indent 0))
  `(health-chart-test-env
     (let ((health-chart-dashboard-backend 'text)
           (health-chart-dashboard-sections '(bullet heatmap)))
       (when (get-buffer health-chart-dashboard-buffer-name)
         (kill-buffer health-chart-dashboard-buffer-name))
       (with-current-buffer (health-charts)
         (unwind-protect (progn ,@body)
           (kill-buffer))))))

(defun health-chart-dashboard-test--goto (marker)
  "Move point to the table row of MARKER."
  (goto-char (health-chart-dashboard--find-marker marker)))

(ert-deftest health-chart-dashboard-test-opens-with-first-person ()
  (health-chart-dashboard-test--with
    (should (derived-mode-p 'health-chart-dashboard-mode))
    (should (equal health-chart-dashboard--person "alex"))
    (should (equal health-chart-dashboard--persons '("alex" "sam")))
    (let ((text (buffer-string)))
      (should (string-match-p "Health charts · alex · category: all · cohort: none · text" text))
      (should (string-match-p "Biomarkers · alex" text))
      (should (string-match-p "Latest vs range · alex" text))
      (should (string-match-p "Out of range · alex" text)))))

(ert-deftest health-chart-dashboard-test-default-person-wins ()
  (let ((health-chart-default-person "sam"))
    (health-chart-test-env
      (let ((health-chart-default-person "sam"))
        (with-current-buffer (health-charts)
          (unwind-protect (should (equal health-chart-dashboard--person "sam"))
            (kill-buffer)))))))

(ert-deftest health-chart-dashboard-test-select-person-and-category ()
  (health-chart-dashboard-test--with
    (health-chart-dashboard-select-person "sam")
    (should (string-match-p "Biomarkers · sam" (buffer-string)))
    (health-chart-dashboard-select-category "lipids")
    (should (string-match-p "category: lipids" (buffer-string)))
    (should (health-chart-dashboard--find-marker "apob"))
    (should-not (health-chart-dashboard--find-marker "tsh"))
    (health-chart-dashboard-select-category "all")
    (should (health-chart-dashboard--find-marker "tsh"))))

(ert-deftest health-chart-dashboard-test-toggles ()
  (health-chart-dashboard-test--with
    (should (string-search "▒" (buffer-string)))
    (health-chart-dashboard-toggle-optimal)
    (should-not health-chart-dashboard--optimal)
    (should-not (string-search "▒" (buffer-substring (health-chart-dashboard--find-marker "ldl_c")
                                                     (point-max))))
    (should (string-match-p "bands: reference\n" (buffer-string)))
    (health-chart-dashboard-toggle-ref)
    (should (string-match-p "bands: \n" (buffer-string)))
    (health-chart-dashboard-toggle-backend)
    (should (eq health-chart-dashboard--backend 'svg))
    ;; the header names the backend actually drawn, text when SVG can't be shown
    (should (string-match-p (if (image-type-available-p 'svg) "· svg ·" "· text ·") (buffer-string)))
    (health-chart-dashboard-toggle-backend)
    (should (eq health-chart-dashboard--backend 'text))))

(ert-deftest health-chart-dashboard-test-ret-opens-time-series ()
  (health-chart-dashboard-test--with
    (health-chart-dashboard-test--goto "vitamin_d")
    (let ((buf (health-chart-dashboard-open)))
      (unwind-protect
          (with-current-buffer buf
            (should (derived-mode-p 'health-chart-plot-mode))
            (should (equal (buffer-name) "*health-chart: Vitamin D*"))
            (should (string-match-p "\\`Vitamin D · alex · ng/mL" (buffer-string)))
            ;; the chart buffer keeps the dashboard's toggles and has its own
            (health-chart-plot-toggle-ref)
            (should-not (string-search "░" (buffer-string)))
            (health-chart-plot-toggle-optimal)
            (should-not (string-search "▒" (buffer-string))))
        (kill-buffer buf)))
    (goto-char (point-min))
    (should-error (health-chart-dashboard-open) :type 'user-error)))

(ert-deftest health-chart-dashboard-test-compare-panel-delta ()
  (health-chart-dashboard-test--with
    (health-chart-dashboard-test--goto "hdl_c")
    (dolist (buf (list (health-chart-dashboard-compare)
                       (health-chart-dashboard-panel)
                       (health-chart-dashboard-delta)))
      (unwind-protect
          (with-current-buffer buf
            (should (> (buffer-size) 100))
            (should-not (string-match-p "no data" (buffer-string))))
        (kill-buffer buf)))))

(ert-deftest health-chart-dashboard-test-row-navigation ()
  (health-chart-dashboard-test--with
    (goto-char (point-min))
    (health-chart-dashboard-next)
    (should (equal (get-text-property (point) 'health-chart-marker) "ldl_c"))
    (health-chart-dashboard-next)
    (should (equal (get-text-property (point) 'health-chart-marker) "hdl_c"))
    (health-chart-dashboard-previous)
    (should (equal (get-text-property (point) 'health-chart-marker) "ldl_c"))))

(ert-deftest health-chart-dashboard-test-source-errors-are-shown ()
  (health-chart-dashboard-test--with
    (let ((health-chart-source-function
           (lambda (&rest _) (signal 'health-chart-source-error
                                     (list "biomarker exited 2: database is locked" :code "source_failed")))))
      (health-chart-dashboard-refresh)
      (should (string-match-p "Source error: biomarker exited 2: database is locked" (buffer-string))))))

(ert-deftest health-chart-dashboard-test-refresh-keeps-point-on-marker ()
  (health-chart-dashboard-test--with
    (health-chart-dashboard-test--goto "tsh")
    (health-chart-dashboard-refresh)
    (should (equal (get-text-property (point) 'health-chart-marker) "tsh"))))

;;; health-chart-dashboard-test.el ends here
