;;; health-chart-transforms-test.el --- the time-of-day-percentiles transform -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'health-chart-eas)

(defun health-chart-transforms-test--run (rows &optional params)
  "Run the transform over ROWS (a list) with PARAMS (a plist)."
  (eas-transform-run
   (vector (append (list :x-eas:transform "time-of-day-percentiles") params))
   (vconcat rows)))

(ert-deftest health-chart-transforms-percentiles-interpolate ()
  (let* ((rows (cl-loop for v in '(10 20 30 40 50)
                        for day from 1
                        collect (list :time (format "2026-03-%02dT08:10" day) :glucose v)))
         (out (health-chart-transforms-test--run rows '(:bucket_minutes 60)))
         (row (aref out 0)))
    (should (= (length out) 1))
    (should (= (plist-get row :tod) 8.0))
    (should (= (plist-get row :n) 5))
    (should (= (plist-get row :p50) 30.0))
    (should (= (plist-get row :p25) 20.0))
    (should (= (plist-get row :p75) 40.0))
    (should (= (plist-get row :p5) 12.0))
    (should (= (plist-get row :p95) 48.0))))

(ert-deftest health-chart-transforms-buckets-by-clock-time ()
  (let ((out (health-chart-transforms-test--run
              '((:time "2026-03-01T00:10" :glucose 100)
                (:time "2026-03-02T00:20" :glucose 120)
                (:time "2026-03-01T00:40" :glucose 90)
                (:time "2026-03-01T23:50" :glucose 80))
              '(:bucket_minutes 30))))
    (should (equal (append (seq-map (lambda (r) (plist-get r :tod)) out) nil) '(0.0 0.5 23.5)))
    (should (equal (append (seq-map (lambda (r) (plist-get r :n)) out) nil) '(2 1 1)))
    (should (= (plist-get (aref out 0) :p50) 110.0))))

(ert-deftest health-chart-transforms-rejects-bad-input ()
  (let ((err (should-error (health-chart-transforms-test--run
                            '((:time "2026-03-01T08:00" :glucose 100)) '(:bucket_minutes 7))
                           :type 'eas-error)))
    (should (equal (plist-get (eas-error-plist err) :code) "INVALID_INPUT")))
  (let ((err (should-error (health-chart-transforms-test--run
                            '((:time "2026-03-01" :glucose 100)))
                           :type 'eas-error)))
    (should (equal (plist-get (eas-error-plist err) :code) "INVALID_INPUT"))
    (should (equal (plist-get (eas-error-plist err) :field) "time"))))

(provide 'health-chart-transforms-test)
;;; health-chart-transforms-test.el ends here
