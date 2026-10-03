;;; health-chart-regression-test.el --- Edge cases found in review -*- lexical-binding: t; -*-

;;; Code:

(require 'health-chart-test-helpers)
(require 'health-chart-batch)

(ert-deftest health-chart-regression-test-time-suffix-is-the-same-day ()
  (health-chart-test-env
    (let ((ms (health-chart-source-normalize-list
               (list (health-chart-test-m :date "2025-01-01T08:00:00" :value 5)
                     (health-chart-test-m :date "2025-01-01T18:00:00" :value 6)
                     (health-chart-test-m :date "2025-02-01T09:00" :value 7)))))
      (should (equal (health-chart-dates ms) '("2025-01-01" "2025-02-01")))
      ;; both draws of 2025-01-01 fall on that day for :until
      (should (= 2 (length (health-chart-filter ms :until "2025-01-01"))))
      (should (= 1 (length (health-chart-filter ms :since "2025-02-01" :until "2025-02-01"))))
      (should (= 2 (length (plist-get (health-chart-model-heatmap ms) :dates))))
      (should (stringp (health-chart-plot 'delta ms :backend 'text :to "2025-02-01"))))))

(ert-deftest health-chart-regression-test-impossible-dates-are-invalid ()
  (should-not (health-chart-date-p "2025-02-31"))
  (should-not (health-chart-date-p "2023-02-29"))
  (should (health-chart-date-p "2024-02-29"))
  (should-error (health-chart-validate 'table (list (health-chart-test-m :date "2025-02-31")))
                :type 'health-chart-invalid-data))

(ert-deftest health-chart-regression-test-rangeless-draw-takes-marker-ranges ()
  (health-chart-test-env
    (let ((ms (list (health-chart-test-m :date "2025-01-01" :value 120 :ref-low 0 :ref-high 100)
                    (health-chart-test-m :date "2025-02-01" :value 50))))
      (should (eq (plist-get (car (health-chart-model-table ms)) :status) 'normal))
      (should (plist-get (car (health-chart-model-bullet ms)) :ref))
      (should (string-match-p "○ normal" (substring-no-properties
                                          (health-chart-plot 'timeseries ms :backend 'text)))))))

(ert-deftest health-chart-regression-test-small-values-keep-labels-distinct ()
  (health-chart-test-env
    (let* ((out (substring-no-properties
                 (health-chart-plot 'timeseries (list (health-chart-test-m :value 1))
                                    :backend 'text)))
           (labels (seq-filter (lambda (s) (string-match-p "┤" s)) (split-string out "\n")))
           (texts (mapcar (lambda (s) (string-trim (car (split-string s "┤")))) labels)))
      (should (equal texts (delete-dups (copy-sequence texts)))))
    (should (string-match-p "latest 0.002"
                            (substring-no-properties
                             (health-chart-plot 'timeseries (list (health-chart-test-m :value 0.001)
                                                                  (health-chart-test-m :value 0.002 :date "2025-02-01"))
                                                :backend 'text))))))

(ert-deftest health-chart-regression-test-sparkline-orders-by-date ()
  (let ((ms (list (health-chart-test-m :date "2025-03-01" :value 3)
                  (health-chart-test-m :date "2025-01-01" :value 1)
                  (health-chart-test-m :date "2025-02-01" :value 2))))
    (should (equal (substring-no-properties (health-chart-plot 'sparkline ms :backend 'text)) "▁▅█"))
    (should (equal (substring-no-properties
                    (health-chart-plot 'sparkline '(("2025-03-01" . 3) ("2025-01-01" . 1)) :backend 'text))
                   "▁█"))
    (should-error (health-chart-plot 'sparkline (cons (health-chart-test-m :marker "tsh") ms))
                  :type 'health-chart-invalid-data)))

(ert-deftest health-chart-regression-test-bad-backend-is-an-error ()
  (should-error (health-chart-plot 'table (health-chart-test-ms "alex") :backend 'SVG)
                :type 'health-chart-invalid-data)
  (should (stringp (plist-get (health-chart-explain 'table nil :backend 'png) :valid))))

(ert-deftest health-chart-regression-test-narrow-svg-stays-valid ()
  (health-chart-test-env
    (dolist (kind '(bullet delta table heatmap))
      (let ((svg (health-chart-plot kind (health-chart-test-ms) :person "alex" :backend 'svg
                                    :pixel-width 300)))
        (should-not (string-match-p "width=\"-" svg))))))

(ert-deftest health-chart-regression-test-dashboard-empty-person ()
  (health-chart-test-env
    (let ((health-chart-dashboard-backend 'text))
      (with-current-buffer (health-chart-dashboard "")
        (unwind-protect
            (progn
              (should (equal health-chart-dashboard--person "alex"))
              (health-chart-dashboard-select-person "")
              (should (equal health-chart-dashboard--person "alex"))
              (should (string-match-p "Biomarkers · alex" (buffer-string))))
          (kill-buffer))))))

(defun health-chart-regression-test--batch (&rest args)
  "Run batch ARGS; return the parsed JSON error code, or nil on success."
  (let* (status
         (out (with-output-to-string (setq status (apply #'health-chart-batch-run args)))))
    (unless (zerop status)
      (alist-get 'code (alist-get 'error (json-parse-string out :object-type 'alist))))))

(ert-deftest health-chart-regression-test-batch-input-checks ()
  (health-chart-test-env
    (cl-flet ((spec (json) (let ((f (make-temp-file "hc-spec" nil ".json")))
                             (with-temp-file f (insert json))
                             f)))
      (let ((files (list (spec "{\"kind\":5,\"data\":[]}")
                         (spec "[1,2]")
                         (spec "{\"kind\":\"table\",\"backend\":\"SVG\",\"data\":[{\"marker\":\"tsh\",\"value\":2,\"date\":\"2025-01-01\"}]}")
                         (spec "{\"kind\":\"timeseries\",\"ref\":null,\"data\":[{\"marker\":\"tsh\",\"value\":2,\"date\":\"2025-01-01\",\"ref_low\":0.4,\"ref_high\":4,\"opt_low\":null}]}"))))
        (unwind-protect
            (progn
              (should (equal (health-chart-regression-test--batch "render" (nth 0 files)) "bad_request"))
              (should (equal (health-chart-regression-test--batch "render" (nth 1 files)) "bad_request"))
              ;; backend names are case-insensitive
              (should-not (health-chart-regression-test--batch "validate" (nth 2 files)))
              ;; null means the default: the reference band still shows
              (let ((out (with-output-to-string (health-chart-batch-run "render" (nth 3 files)))))
                (should (string-search "reference" out))))
          (mapc #'delete-file files))))))

;;; health-chart-regression-test.el ends here
