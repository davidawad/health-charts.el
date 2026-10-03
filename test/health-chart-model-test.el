;;; health-chart-model-test.el --- What each kind draws, independent of backend -*- lexical-binding: t; -*-

;;; Code:

(require 'health-chart-test-helpers)

(ert-deftest health-chart-model-test-series-selects-marker-and-person ()
  (health-chart-test-env
    (let ((model (health-chart-model-series (health-chart-test-ms) :marker "hdl_c" :person "sam")))
      (should (equal (plist-get model :marker) "hdl_c"))
      (should (equal (plist-get model :label) "HDL-C"))
      (should (equal (plist-get model :person) "sam"))
      (should (= 1 (length (plist-get model :lines))))
      (should (= 6 (length (plist-get (car (plist-get model :lines)) :points))))
      (should (equal (plist-get model :ref) '(40)))
      (should (equal (plist-get model :opt) '(60)))
      (should (equal (plist-get (plist-get model :latest) :date) "2025-06-02")))
    ;; defaults: the first marker and person present
    (let ((model (health-chart-model-series (health-chart-test-ms))))
      (should (equal (plist-get model :marker) "ldl_c"))
      (should (equal (plist-get model :person) "alex")))
    (should-not (health-chart-model-series nil))))

(ert-deftest health-chart-model-test-series-compare-has-a-line-per-person ()
  (health-chart-test-env
    (let ((model (health-chart-model-series (health-chart-test-ms) :marker "ldl_c" :compare t)))
      (should (plist-get model :compare))
      (should-not (plist-get model :person))
      (should (equal (mapcar (lambda (l) (plist-get l :name)) (plist-get model :lines))
                     '("alex" "sam"))))))

(ert-deftest health-chart-model-test-band-toggles ()
  (health-chart-test-env
    (let ((ms (health-chart-test-ms "alex")))
      (should (plist-get (health-chart-model-series ms) :ref))
      (should-not (plist-get (health-chart-model-series ms :ref nil) :ref))
      (should-not (plist-get (health-chart-model-series ms :optimal nil) :opt))
      (let ((health-chart-show-ref-range nil))
        (should-not (plist-get (health-chart-model-series ms) :ref))
        (should (plist-get (health-chart-model-series ms :ref t) :ref))))))

(ert-deftest health-chart-model-test-y-range-shows-near-edges-only ()
  ;; values 88..131 mg/dL: the 100 and 70 edges are close enough to show,
  ;; the 0 reference floor is not (it would flatten the line)
  (health-chart-test-env
    (pcase-let ((`(,lo . ,hi) (plist-get (health-chart-model-series (health-chart-test-ms "alex")) :y-range)))
      (should (< lo 70))
      (should (> lo 50))
      (should (> hi 131)))))

(ert-deftest health-chart-model-test-table-rows ()
  (health-chart-test-env
    (let ((rows (health-chart-model-table (health-chart-test-ms) :person "alex")))
      (should (= 9 (length rows)))
      (let ((ldl (car rows)))
        (should (equal (plist-get ldl :values) '(131 124 108 96 112 88)))
        (should (eq (plist-get ldl :status) 'suboptimal))
        (should (equal (plist-get ldl :ref) "0–100"))
        (should (equal (plist-get ldl :opt) "≤70"))))))

(ert-deftest health-chart-model-test-bullet-domain-covers-value-and-bands ()
  (health-chart-test-env
    (dolist (row (health-chart-model-bullet (health-chart-test-ms) :person "alex"))
      (pcase-let ((`(,lo . ,hi) (plist-get row :domain)))
        (should (< lo (plist-get row :value) hi))
        (dolist (edge (list (car (plist-get row :ref)) (cdr (plist-get row :ref))))
          (when edge (should (<= lo edge hi))))
        ;; never below zero for an all-positive marker
        (should (>= lo 0))))))

(ert-deftest health-chart-model-test-heatmap-cells ()
  (health-chart-test-env
    (let* ((ms (append (health-chart-test-ms "alex")
                       (list (health-chart-test-m :marker "tsh" :date "2025-07-01" :value 5.0
                                                  :ref-low 0.4 :ref-high 4.0))))
           (model (health-chart-model-heatmap ms))
           (tsh (seq-find (lambda (r) (equal (plist-get r :marker) "tsh")) (plist-get model :rows)))
           (ldl (car (plist-get model :rows))))
      (should (= 7 (length (plist-get model :dates))))
      (should (null (car (last (plist-get ldl :cells)))))
      (should (= 4 (plist-get ldl :out)))
      (should (= 1 (plist-get tsh :out))))))

(ert-deftest health-chart-model-test-delta-verdicts ()
  (health-chart-test-env
    (let* ((model (health-chart-model-delta (health-chart-test-ms) :person "alex"))
           (rows (plist-get model :rows))
           (row (lambda (marker) (seq-find (lambda (r) (equal (plist-get r :marker) marker)) rows))))
      (should (equal (plist-get model :from) "2025-03-03"))
      (should (equal (plist-get model :to) "2025-06-02"))
      (should (eq (plist-get (funcall row "ldl_c") :verdict) 'improved))
      (should (eq (plist-get (funcall row "crp") :verdict) 'worsened))
      (should (eq (plist-get (funcall row "tsh") :verdict) 'on-target))
      (should (= (plist-get (funcall row "ldl_c") :change) -24))
      (should (< (abs (- (plist-get (funcall row "ldl_c") :pct) -21.43)) 0.01)))
    (let ((model (health-chart-model-delta (health-chart-test-ms) :person "alex"
                                           :from "2024-03-04" :to "2024-06-03")))
      (should (= 9 (length (plist-get model :rows)))))
    (let ((steady (health-chart-model-delta
                   (list (health-chart-test-m :date "2025-01-01" :value 120 :ref-high 100)
                         (health-chart-test-m :date "2025-02-01" :value 120 :ref-high 100)))))
      (should (eq (plist-get (car (plist-get steady :rows)) :verdict) 'steady)))
    ;; one draw only: nothing to compare
    (should-not (plist-get (health-chart-model-delta (list (health-chart-test-m))) :rows))))

(ert-deftest health-chart-model-test-resample ()
  (should (equal (health-chart-model-resample '(1 2 3) 5) '(1 2 3)))
  (should (equal (health-chart-model-resample '(1 3 5 7) 2) '(2.0 6.0))))

;;; health-chart-model-test.el ends here
