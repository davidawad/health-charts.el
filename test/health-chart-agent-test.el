;;; health-chart-agent-test.el --- discover / validate / explain / describe -*- lexical-binding: t; -*-

;; The agent surface: every claim it makes about the package is checked
;; here against what the renderers actually do.

;;; Code:

(require 'health-chart-test-helpers)
(require 'json)

(ert-deftest health-chart-agent-test-list-kinds-matches-registry ()
  (should (equal (mapcar #'car (health-chart-list-kinds))
                 '(timeseries panel table bullet heatmap compare delta sparkline
                   scorecard cohort staleness)))
  (dolist (k (health-chart-list-kinds))
    (should (plist-get (cdr k) :doc))
    (should (assq (plist-get (cdr k) :shape) health-chart-shapes))))

(ert-deftest health-chart-agent-test-describe-kind-example-is-valid ()
  (dolist (k (mapcar #'car health-chart-kinds))
    (let ((d (health-chart-describe-kind k)))
      (should (plist-get d :renderers-defined))
      (should (plist-get d :shape-doc))
      (should (eq t (health-chart-validate k (plist-get d :example)))))))

(ert-deftest health-chart-agent-test-unknown-kind-names-the-fix ()
  (let ((err (should-error (health-chart-plot 'pie nil) :type 'health-chart-unknown-kind)))
    (should (string-match-p "timeseries, panel" (cadr err)))
    (should (equal (plist-get (cddr err) :code) "unknown_kind"))))

(ert-deftest health-chart-agent-test-validate-locates-bad-element ()
  (let* ((good (health-chart-test-m))
         (err (should-error (health-chart-validate 'table (list good good '((marker . "x") (date . "2025-01-01") (value . "high"))))
                            :type 'health-chart-invalid-data)))
    (should (equal (plist-get (cddr err) :index) 2))
    (should (equal (plist-get (cddr err) :code) "invalid_data"))
    (should (string-match-p "numeric \"value\"" (cadr err))))
  (let ((err (should-error (health-chart-validate 'table (list (health-chart-test-m :date "03/01/2025")))
                           :type 'health-chart-invalid-data)))
    (should (string-match-p "YYYY-MM-DD" (cadr err))))
  (let ((err (should-error (health-chart-validate 'table (list (health-chart-test-m :ref-low 100 :ref-high 0)))
                           :type 'health-chart-invalid-data)))
    (should (string-match-p "swap" (cadr err))))
  (should-error (health-chart-validate 'table '(42)) :type 'health-chart-invalid-data)
  (should-error (health-chart-validate 'sparkline '(1 "x" 3)) :type 'health-chart-invalid-data)
  (should (eq t (health-chart-validate 'table nil))))

(ert-deftest health-chart-agent-test-validate-checks-selecting-props ()
  (let ((ms (health-chart-test-ms)))
    (let ((err (should-error (health-chart-validate 'timeseries ms :marker "ldl")
                             :type 'health-chart-invalid-data)))
      (should (equal (plist-get (cddr err) :code) "unknown_marker"))
      (should (string-match-p "ldl_c" (cadr err))))
    (let ((err (should-error (health-chart-plot 'delta ms :from "2020-01-01")
                             :type 'health-chart-invalid-data)))
      (should (equal (plist-get (cddr err) :code) "unknown_date")))))

(ert-deftest health-chart-agent-test-validate-accepts-an-envelope ()
  (should (eq t (health-chart-validate
                 'table (json-parse-string (health-chart-test-read "biomarker-query.json")
                                           :object-type 'alist :array-type 'list :null-object nil))))
  (let ((err (should-error (health-chart-validate 'table '((schema . "biomarker/v9") (measurements)))
                           :type 'health-chart-source-error)))
    (should (equal (plist-get (cddr err) :code) "schema_mismatch"))))

(ert-deftest health-chart-agent-test-explain-is-the-plan-plot-follows ()
  (health-chart-test-env
    (let* ((ms (health-chart-test-ms))
           (plan (health-chart-explain 'timeseries ms :backend 'text :marker "tsh" :width 50)))
      (should (eq (plist-get plan :valid) t))
      (should (eq (plist-get plan :backend) 'text))
      (should (eq (plist-get plan :renderer) 'health-chart-text-timeseries))
      (should (equal (plist-get plan :args) '(:marker "tsh" :width 50)))
      (should (= (plist-get plan :points) 108))
      (should (equal (plist-get plan :from) "2024-03-04"))
      ;; the plan's renderer + args reproduce plot's output exactly
      (should (equal (apply (plist-get plan :renderer) ms (plist-get plan :args))
                     (health-chart-plot 'timeseries ms :backend 'text :marker "tsh" :width 50))))
    (let ((plan (health-chart-explain 'bullet '((marker . "x")) :backend 'svg :pixel-width 500)))
      (should (stringp (plist-get plan :valid)))
      (should (eq (plist-get plan :renderer) 'health-chart-svg-bullet))
      (should (equal (plist-get plan :args) '(:width 500)))
      (should-not (plist-get plan :points)))))

(ert-deftest health-chart-agent-test-describe-round-trips-json ()
  (let* ((d (health-chart-describe))
         (json (json-parse-string (json-encode d) :object-type 'plist)))
    (should (equal (plist-get json :package) "health-chart"))
    (should (= (length (plist-get json :kinds)) (length health-chart-kinds)))
    (should (equal (plist-get (plist-get json :source) :schema) "biomarker/v1"))
    ;; every advertised entry point exists
    (dolist (group health-chart-entry-points)
      (dolist (fn (cdr group))
        (should (or (fboundp fn) (boundp fn)))))))

(ert-deftest health-chart-agent-test-register-kind ()
  (let ((health-chart-kinds (copy-alist health-chart-kinds)))
    (health-chart-register-kind 'count :shape 'measurements
                                :text (lambda (ms &rest _) (format "%d draws" (length ms)))
                                :svg (lambda (ms &rest _) (format "<svg>%d</svg>" (length ms)))
                                :doc "Count draws.")
    (should (equal (health-chart-plot 'count (health-chart-test-ms "sam") :backend 'text) "54 draws"))
    (should (assq 'count (health-chart-list-kinds)))
    (should-error (health-chart-register-kind 'bad :shape 'nope) :type 'health-chart-error)))

(ert-deftest health-chart-agent-test-doctor ()
  (let ((health-chart-source-function #'health-chart-source-static))
    (let ((rows (health-chart-doctor-checks)))
      (dolist (k health-chart-kinds)
        (let ((row (seq-find (lambda (r) (equal (plist-get r :name) (format "kind %s" (car k)))) rows)))
          (should row)
          (should (eq (plist-get row :status) 'pass))))
      (should (cl-every (lambda (r) (memq (plist-get r :status) '(pass fail skip))) rows)))
    (with-current-buffer (window-buffer)
      (let ((rows (health-chart-doctor)))
        (should rows)
        (with-current-buffer "*health-chart doctor*"
          (should (string-match-p "PASS +kind timeseries" (buffer-string))))))))

;;; health-chart-agent-test.el ends here
