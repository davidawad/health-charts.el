;;; health-chart-indicator-test.el --- Indicator catalog, values, cohorts -*- lexical-binding: t; -*-

;; The indicator layer against a synthetic static catalog
;; (fixtures/indicator-catalog.json) and synthetic values
;; (fixtures/indicator-values.json).  Golden files pin the scorecard,
;; cohort and staleness kinds in both backends.

;;; Code:

(require 'health-chart-test-helpers)
(require 'health-chart-batch)
(require 'dom)
(require 'json)

(defun health-chart-indicator-test--json (name)
  "Fixture NAME parsed as the batch CLI parses JSON."
  (json-parse-string (health-chart-test-read name) :object-type 'alist :array-type 'list
                     :null-object :null :false-object nil))

(defun health-chart-indicator-test--values ()
  "The synthetic indicator values fixture, canonical."
  (health-chart-indicator-normalize-values
   (health-chart-indicator-test--json "indicator-values.json")))

(defmacro health-chart-indicator-test--with-catalog (&rest body)
  "Run BODY in the test env with the static fixture catalog."
  (declare (indent 0) (debug t))
  `(health-chart-test-env
     (let ((health-chart-indicator-catalog-function #'health-chart-indicator-catalog-static)
           (health-chart-indicator-catalog-static-data
            (health-chart-indicator-test--json "indicator-catalog.json"))
           (health-chart-indicator-tag "health")
           (health-chart-indicator-due-days 120)
           (health-chart-indicator-stale-days 365))
       ,@body)))

(defun health-chart-indicator-test--boom (&rest args)
  "Fail the test: a pure plan called an effectful function with ARGS."
  (error "Pure plan made a call: %S" args))

;; -----------------------------------------------------------------------
;; Catalog and registry view
;; -----------------------------------------------------------------------

(ert-deftest health-chart-indicator-test-record-normalizes ()
  (health-chart-indicator-test--with-catalog
    (let ((r (health-chart-indicator-catalog-get "health.cardio.apob")))
      (should (equal (plist-get r :id) "health.cardio.apob"))
      (should (equal (plist-get r :kind) "indicator"))
      (should (equal (plist-get r :tags) '("health" "cardio")))
      (should (equal (plist-get r :bounds) '(nil 90)))
      (should (eq (plist-get r :direction) 'lower-better))
      (should (equal (plist-get r :subject-key) "apob"))
      (should (equal (plist-get r :time-basis) "draw"))
      (should (plist-get r :recipe-p))
      ;; canonical records pass through
      (should (equal (health-chart-indicator-normalize-record r) r)))
    (should-not (health-chart-indicator-catalog-get "health.nope"))))

(ert-deftest health-chart-indicator-test-direction-and-bounds-spellings ()
  (dolist (pair '(("lower_is_better" . lower-better) (down . lower-better)
                  ("Higher-Is-Better" . higher-better) ("target_range" . in-range)
                  ("neutral" . neutral) ("sideways" . neutral) (nil . nil) (:null . nil)))
    (should (eq (health-chart-indicator-direction (car pair)) (cdr pair))))
  (should (equal (health-chart-indicator-bounds '((min . 0) (max . 100))) '(0 100)))
  (should (equal (health-chart-indicator-bounds '((min . :null) (max . 5))) '(nil 5)))
  (should (equal (health-chart-indicator-bounds [1 2]) '(1 2)))
  (should (equal (health-chart-indicator-bounds '(1 . 2)) '(1 2)))
  (should (equal (health-chart-indicator-bounds '(:min 3)) '(3 nil)))
  (should-not (health-chart-indicator-bounds '((min . :null) (max . :null)))))

(ert-deftest health-chart-indicator-test-list-filters-by-tag ()
  (health-chart-indicator-test--with-catalog
    (should (= 12 (length (health-chart-indicator-list))))
    (should (= 13 (length (health-chart-indicator-list :tag nil))))
    (should (equal (mapcar (lambda (r) (plist-get r :id)) (health-chart-indicator-list :tag "cardio"))
                   '("health.cardio.apob" "health.cardio.lp-a")))
    (let ((health-chart-indicator-tag nil))
      (should (= 13 (length (health-chart-indicator-list)))))))

(ert-deftest health-chart-indicator-test-list-probes-when-catalog-cannot-list ()
  (health-chart-indicator-test--with-catalog
    (let ((health-chart-indicator-catalog-function
           (lambda (id) (and id (health-chart-indicator-catalog-static id)))))
      (should (equal (mapcar (lambda (r) (plist-get r :id)) (health-chart-indicator-list))
                     (health-chart-indicator-known-ids))))))

(ert-deftest health-chart-indicator-test-list-probes-lookup-only-catalog ()
  (health-chart-indicator-test--with-catalog
    (let ((health-chart-indicator-catalog-function
           (lambda (id) (unless id (error "Lookup needs an id"))
             (health-chart-indicator-catalog-static id))))
      (should (= 12 (length (health-chart-indicator-list)))))
    (let ((health-chart-indicator-catalog-function (lambda (_) (error "Synthetic outage"))))
      (should-error (health-chart-indicator-list) :type 'health-chart-catalog-error))))

(ert-deftest health-chart-indicator-test-catalog-errors-are-typed ()
  (let ((health-chart-indicator-catalog-function nil))
    (let ((err (should-error (health-chart-indicator-list) :type 'health-chart-catalog-error)))
      (should (equal (plist-get (cddr err) :code) "catalog_missing"))
      (should (string-match-p "health-chart-indicator-catalog-function" (cadr err)))))
  (let ((health-chart-indicator-catalog-function (lambda (_) (error "Synthetic outage"))))
    (let ((err (should-error (health-chart-indicator-catalog-get "x")
                             :type 'health-chart-catalog-error)))
      (should (equal (plist-get (cddr err) :code) "catalog_failed"))
      (should (string-match-p "Synthetic outage" (cadr err))))))

(ert-deftest health-chart-indicator-test-describe-and-its-plan ()
  (health-chart-indicator-test--with-catalog
    (let ((d (health-chart-indicator-describe "health.vitamin-d")))
      (should (eq (plist-get d :in-catalog) t))
      (should (plist-get d :evaluable))
      (should (equal (plist-get (plist-get d :record) :name) "25-hydroxy vitamin D")))
    (should-not (plist-get (health-chart-indicator-describe "finance.market.rsi-14") :evaluable))
    (let ((health-chart-indicator-catalog-function #'health-chart-indicator-test--boom))
      (let ((plan (health-chart-indicator-describe-explain "health.vitamin-d")))
        (should (equal (plist-get plan :calls)
                       '((health-chart-indicator-test--boom "health.vitamin-d"))))
        (should (plist-get plan :evaluable)))
      (let ((plan (health-chart-indicator-list-explain :tag "cardio")))
        (should (equal (plist-get plan :tag) "cardio"))
        (should (equal (plist-get plan :calls) '((health-chart-indicator-test--boom nil))))
        (should (= 12 (length (plist-get plan :fallback))))))
    (let ((health-chart-indicator-catalog-function nil))
      (should (eq (plist-get (health-chart-indicator-describe "health.vitamin-d") :in-catalog)
                  'unknown))
      (should (stringp (plist-get (health-chart-indicator-list-explain) :error))))))

;; -----------------------------------------------------------------------
;; Evaluation and status
;; -----------------------------------------------------------------------

(defun health-chart-indicator-test--eval (id &rest params)
  "Evaluate ID over alex's example data as of 2025-08-01, with PARAMS."
  (apply #'health-chart-indicator-evaluate id (health-chart-test-ms "alex")
         :as-of "2025-08-01" params))

(ert-deftest health-chart-indicator-test-evaluate-measures ()
  (health-chart-test-env
    (let ((apob (health-chart-indicator-test--eval "health.cardio.apob")))
      (should (equal (plist-get apob :value) 84))
      (should (equal (plist-get apob :label) "ApoB"))
      (should (equal (plist-get apob :series) '(104 99 91 86 93 84)))
      (should (eq (health-chart-indicator-status apob) 'suboptimal))
      (should (eq (health-chart-indicator-trend apob) 'improved)))
    (let ((lpa (health-chart-indicator-test--eval "health.cardio.lp-a")))
      (should-not (plist-get lpa :value))
      (should (equal (plist-get lpa :marker) "lpa"))
      (should (eq (health-chart-indicator-status lpa) 'unknown)))
    ;; candidate markers: hs_crp is absent, crp is present
    (should (equal (plist-get (health-chart-indicator-test--eval "health.inflammation.hs-crp") :marker)
                   "crp"))
    (let ((pos (health-chart-indicator-test--eval "health.biomarker.range-position" :marker "crp")))
      (should (= (plist-get pos :value) 1.133))
      (should (eq (health-chart-indicator-status pos) 'high)))
    (let ((slope (health-chart-indicator-test--eval "health.biomarker.trend-slope" :marker "ldl_c")))
      (should (< (plist-get slope :value) 0))
      (should (equal (plist-get slope :unit) "mg/dL/yr"))
      (should (eq (health-chart-indicator-trend slope) 'falling)))
    (let ((age (health-chart-indicator-test--eval "health.biomarker.days-since-draw")))
      (should (= (plist-get age :value) 60))
      (should (equal (plist-get age :label) "Days since draw"))
      (should (eq (health-chart-indicator-status age) 'normal)))
    (let ((out (health-chart-indicator-test--eval "health.panel.out-of-range-count")))
      (should (= (plist-get out :value) 1))
      (should (= (length (plist-get out :series)) 6))
      (should (eq (health-chart-indicator-status out) 'high)))))

(ert-deftest health-chart-indicator-test-evaluate-errors-name-the-fix ()
  (let ((err (should-error (health-chart-indicator-test--eval "health.nope")
                           :type 'health-chart-unknown-indicator)))
    (should (equal (plist-get (cddr err) :code) "unknown_indicator"))
    (should (string-match-p "health-chart-indicator-evaluators" (cadr err))))
  (let ((err (should-error (health-chart-indicator-test--eval "health.biomarker.latest")
                           :type 'health-chart-unknown-indicator)))
    (should (equal (plist-get (cddr err) :code) "missing_marker"))))

(ert-deftest health-chart-indicator-test-record-fills-semantics ()
  (health-chart-test-env
    (let* ((record (list :id "health.biomarker.latest" :subject-kind "biomarker"
                         :subject-key "tsh" :direction 'neutral :bounds '(0.5 2.5)
                         :unit "mIU/L" :recipe-p t))
           (v (health-chart-indicator-test--eval "health.biomarker.latest" :record record)))
      (should (equal (plist-get v :marker) "tsh"))
      (should (eq (plist-get v :direction) 'neutral))
      (should (equal (plist-get v :bounds) '(0.5 2.5))))))

(ert-deftest health-chart-indicator-test-status-by-direction-and-bounds ()
  (pcase-dolist (`(,value ,direction ,bounds ,status)
                 '((5 lower-better (2 4) high) (3 lower-better (2 4) normal)
                   (1 lower-better (2 4) optimal) (1 higher-better (2 4) low)
                   (5 higher-better (2 4) optimal) (3 higher-better (2 4) normal)
                   (5 in-range (2 4) high) (1 neutral (2 4) low) (3 nil (2 4) normal)
                   (3 lower-better nil unknown) (nil lower-better (2 4) unknown)))
    (should (eq (health-chart-indicator-status
                 (list :value value :direction direction :bounds bounds))
                status)))
  ;; ranges outrank bounds, an explicit status outranks both
  (should (eq (health-chart-indicator-status '(:value 95 :ref-high 100 :opt-high 70 :bounds (0 50)))
              'suboptimal))
  (should (eq (health-chart-indicator-status '(:value 95 :status optimal)) 'optimal)))

(ert-deftest health-chart-indicator-test-trend-verdicts ()
  (pcase-dolist (`(,series ,direction ,bounds ,verdict)
                 '(((5 3) lower-better nil improved) ((3 5) lower-better nil worsened)
                   ((3 5) higher-better nil improved) ((100 100.5) lower-better nil steady)
                   ((20 35) in-range (30 100) improved) ((40 60) in-range (30 100) on-target)
                   ((1 2) neutral nil rising) ((2 1) nil nil falling) ((3) lower-better nil nil)))
    (should (eq (health-chart-indicator-trend (list :series series :direction direction :bounds bounds))
                verdict)))
  (should (equal (health-chart-indicator-trend-label 'improved '(5 3)) "↘ improved"))
  (should (equal (health-chart-indicator-trend-label nil nil) "")))

;; -----------------------------------------------------------------------
;; Values: normalize and validate
;; -----------------------------------------------------------------------

(ert-deftest health-chart-indicator-test-values-normalize-from-json ()
  (let ((vs (health-chart-indicator-test--values)))
    (should (= 6 (length vs)))
    (should (equal (plist-get (nth 1 vs) :bounds) '(nil 75)))
    (should (equal (plist-get (nth 2 vs) :bounds) '(nil 5.7)))
    (should (eq (plist-get (nth 3 vs) :direction) 'in-range))
    (should (null (plist-get (nth 5 vs) :value)))
    (should (equal (health-chart-indicator-normalize-values vs) vs))
    (should (eq t (health-chart-validate 'scorecard vs)))))

(ert-deftest health-chart-indicator-test-validate-locates-bad-value ()
  (let* ((good '(:id "a" :value 1))
         (err (should-error (health-chart-validate 'scorecard (list good good '((id . "c") (value . "high"))))
                            :type 'health-chart-invalid-data)))
    (should (equal (plist-get (cddr err) :index) 2))
    (should (equal (plist-get (cddr err) :code) "invalid_data")))
  (dolist (bad '((:value 1) (:id "a" :date "08/01/2025") (:id "a" :series (1 "x"))
                 (:id "a" :bounds (5 1)) (:id "a" :status great)))
    (should-error (health-chart-validate 'scorecard (list bad)) :type 'health-chart-invalid-data))
  (let ((vs (health-chart-indicator-test--values)))
    (should-error (health-chart-validate 'staleness vs :as-of "soon") :type 'health-chart-invalid-data)
    (should-error (health-chart-validate 'staleness vs :stale-days -1) :type 'health-chart-invalid-data)))

(ert-deftest health-chart-indicator-test-explain-summarizes-values ()
  (let ((plan (health-chart-explain 'scorecard (health-chart-indicator-test--values) :backend 'text)))
    (should (eq (plist-get plan :valid) t))
    (should (eq (plist-get plan :shape) 'indicators))
    (should (eq (plist-get plan :renderer) 'health-chart-text-scorecard))
    (should (= (plist-get plan :points) 6))
    (should (equal (plist-get plan :cohorts) ["cardio"]))
    (should (= (plist-get plan :out-of-range) 2))))

;; -----------------------------------------------------------------------
;; Rendering
;; -----------------------------------------------------------------------

(defconst health-chart-indicator-test--kinds '(scorecard cohort staleness)
  "The indicator chart kinds.")

(ert-deftest health-chart-indicator-test-text-goldens ()
  (health-chart-indicator-test--with-catalog
    (dolist (kind health-chart-indicator-test--kinds)
      (health-chart-test-golden
       (format "%s.txt" kind)
       (health-chart-plot kind (health-chart-indicator-test--values) :backend 'text)))))

(ert-deftest health-chart-indicator-test-svg-goldens ()
  (health-chart-indicator-test--with-catalog
    (dolist (kind health-chart-indicator-test--kinds)
      (let ((svg (health-chart-plot kind (health-chart-indicator-test--values) :backend 'svg)))
        (health-chart-test-golden (format "%s.svg" kind) svg)
        (should (string-match-p (format "<desc>health-chart %s: 6 indicator values" kind) svg))
        (should-not (string-match-p "width=\"-" svg))
        (when (fboundp 'libxml-parse-xml-region)
          (let ((dom (with-temp-buffer (insert svg)
                                       (libxml-parse-xml-region (point-min) (point-max)))))
            (should (eq (dom-tag dom) 'svg))
            (should (> (length (dom-by-tag dom 'title)) 6))))))))

(ert-deftest health-chart-indicator-test-every-status-has-glyph-and-word ()
  (health-chart-indicator-test--with-catalog
    (let ((card (substring-no-properties
                 (health-chart-plot 'scorecard (health-chart-indicator-test--values) :backend 'text)))
          (stale (substring-no-properties
                  (health-chart-plot 'staleness (health-chart-indicator-test--values) :backend 'text))))
      (dolist (label '("◐ suboptimal" "▲ high" "▼ low" "○ normal" "? n/a"))
        (should (string-search label card)))
      (dolist (label '("● fresh" "◐ due" "▲ stale" "? undated"))
        (should (string-search label stale))))))

(ert-deftest health-chart-indicator-test-rows-carry-marker-properties ()
  (health-chart-indicator-test--with-catalog
    (let ((out (health-chart-plot 'scorecard (health-chart-indicator-test--values) :backend 'text)))
      (with-temp-buffer
        (insert out)
        (goto-char (point-min))
        (search-forward "Vitamin D")
        (should (equal (get-text-property (point) 'health-chart-marker) "vitamin_d"))
        (should (equal (get-text-property (point) 'health-chart-indicator) "health.vitamin-d"))))))

(ert-deftest health-chart-indicator-test-staleness-as-of-defaults ()
  (health-chart-test-env
    (let* ((vs (health-chart-indicator-test--values))
           (model (health-chart-model-staleness vs)))
      (should (equal (plist-get model :as-of) "2025-08-01"))
      (should (equal (mapcar (lambda (r) (plist-get r :state)) (plist-get model :rows))
                     '(stale due due fresh fresh undated)))
      (should (equal (plist-get (health-chart-model-staleness vs :as-of "2025-06-02" :due-days 10) :as-of)
                     "2025-06-02")))))

(ert-deftest health-chart-indicator-test-batch-renders-values ()
  (health-chart-test-env
    (let ((spec (make-temp-file "hc-ind" nil ".json")))
      (unwind-protect
          (progn
            (with-temp-file spec
              (insert "{\"kind\":\"staleness\",\"backend\":\"text\",\"as_of\":\"2025-09-01\",\"data\":"
                      (health-chart-test-read "indicator-values.json") "}"))
            (let ((out (with-output-to-string (health-chart-batch-run "render" spec))))
              (should (string-search "as of 2025-09-01" out))
              (should (string-search "▲ stale" out))))
        (delete-file spec)))))

(defun health-chart-indicator-test--batch-code (&rest args)
  "Run batch ARGS; return the JSON error code, or nil on success."
  (let* (status
         (out (with-output-to-string (setq status (apply #'health-chart-batch-run args)))))
    (unless (zerop status)
      (alist-get 'code (alist-get 'error (json-parse-string out :object-type 'alist))))))

(ert-deftest health-chart-indicator-test-batch-cohort-commands ()
  (health-chart-test-env
    (let ((health-chart-indicator-catalog-function nil))
      (let ((out (with-output-to-string
                   (should (= 0 (health-chart-batch-run "cohort" "cardio"
                                                        "{\"person\":\"sam\",\"as_of\":\"2025-08-01\"}"))))))
        (should (string-search "Indicators · cardio" out))
        (should (string-search "ApoB" out)))
      (let ((out (with-output-to-string
                   (health-chart-batch-run "cohort" "vitamins" "{\"kind\":\"staleness\",\"as_of\":\"2025-08-01\"}"))))
        (should (string-search "Days since draw · vitamins" out)))
      (let* ((out (with-output-to-string
                    (health-chart-batch-run "cohort-explain" "cardio" "{\"person\":\"alex\"}")))
             (plan (json-parse-string out :object-type 'alist :array-type 'list)))
        (should (eq (alist-get 'valid plan) t))
        (should (equal (alist-get 'id (car (alist-get 'members plan))) "health.cardio.apob"))
        (should (equal (alist-get 'renderer (alist-get 'plot plan)) "health-chart-text-scorecard")))
      (let ((out (with-output-to-string (health-chart-batch-run "cohorts"))))
        (should (= 5 (length (json-parse-string out)))))
      (should (equal (health-chart-indicator-test--batch-code "cohort") "bad_request"))
      (should (equal (health-chart-indicator-test--batch-code "cohort" "nope") "unknown_cohort")))))

;; -----------------------------------------------------------------------
;; Cohorts
;; -----------------------------------------------------------------------

(ert-deftest health-chart-indicator-test-default-cohorts-resolve ()
  (should (equal (health-chart-cohort-names) '(cardio metabolic inflammation vitamins overview)))
  (dolist (c (health-chart-list-cohorts))
    (should (= 0 (plist-get (cdr c) :unresolvable)))
    (should (stringp (plist-get (cdr c) :doc))))
  (dolist (row (health-chart-cohort-doctor-checks))
    (should-not (eq (plist-get row :status) 'fail))))

(ert-deftest health-chart-indicator-test-unresolvable-cohort-is-typed ()
  (let ((err (should-error (health-chart-resolve-cohort 'nope)
                           :type 'health-chart-unresolvable-cohort)))
    (should (equal (plist-get (cddr err) :code) "unknown_cohort"))
    (should (string-match-p "cardio" (cadr err))))
  (let ((health-chart-indicator-cohorts
         '((broken :doc "d" :members ((:indicator "health.cardio.apob")
                                      (:indicator "health.made-up")
                                      (:params (:marker "x")))))))
    (let ((err (should-error (health-chart-resolve-cohort 'broken)
                             :type 'health-chart-unresolvable-cohort)))
      (should (equal (plist-get (cddr err) :code) "unresolvable_cohort"))
      (should (string-match-p "health.made-up" (cadr err))))
    (should (equal (cdr (car (health-chart-list-cohorts)))
                   '(:doc "d" :members 3 :resolvable 1 :unresolvable 2)))
    (let ((row (car (last (health-chart-cohort-doctor-checks)))))
      (should (equal (plist-get row :name) "cohort:broken"))
      (should (eq (plist-get row :status) 'fail)))
    (should (equal (mapcar (lambda (m) (plist-get m :status))
                           (plist-get (health-chart-describe-cohort 'broken) :members))
                   '(resolved unresolvable unresolvable)))))

(ert-deftest health-chart-indicator-test-describe-cohort-probes-catalog ()
  (health-chart-indicator-test--with-catalog
    (let ((members (plist-get (health-chart-describe-cohort "cardio") :members)))
      (should (equal (mapcar (lambda (m) (plist-get m :catalog-live)) members) '(t t t)))
      (should (string-match-p "Apolipoprotein B" (plist-get (car members) :catalog-detail))))
    (let ((health-chart-indicator-catalog-function (lambda (_) nil)))
      (should (eq :false (plist-get (car (plist-get (health-chart-describe-cohort 'cardio) :members))
                                    :catalog-live))))
    (let ((health-chart-indicator-catalog-function (lambda (_) (error "Synthetic outage"))))
      (let ((m (car (plist-get (health-chart-describe-cohort 'cardio) :members))))
        (should (eq :error (plist-get m :catalog-live)))
        (should (string-match-p "Synthetic outage" (plist-get m :catalog-detail)))))
    (let ((health-chart-indicator-catalog-function nil))
      (should (eq :unknown (plist-get (car (plist-get (health-chart-describe-cohort 'cardio) :members))
                                      :catalog-live))))))

(ert-deftest health-chart-indicator-test-explain-twins-are-pure ()
  (health-chart-indicator-test--with-catalog
    (let ((health-chart-indicator-catalog-function #'health-chart-indicator-test--boom)
          (health-chart-source-function #'health-chart-indicator-test--boom))
      (let ((plan (health-chart-describe-cohort-explain 'cardio)))
        (should (eq (plist-get plan :valid) t))
        (should (= 3 (length (plist-get plan :calls))))
        (should (equal (plist-get (car (plist-get plan :members)) :status) 'resolved)))
      (let ((plan (health-chart-cohort-values-explain 'vitamins :person "alex" :as-of "2025-08-01")))
        (should (eq (plist-get plan :valid) t))
        (should (equal (plist-get plan :fetch)
                       '(:function health-chart-indicator-test--boom :command query
                                   :args (:person "alex"))))
        (should (equal (mapcar #'cadr (plist-get (plist-get plan :catalog) :calls))
                       '("health.vitamin-d" "health.biomarker.days-since-draw")))
        (should (equal (plist-get plan :as-of) "2025-08-01")))
      (let ((plan (health-chart-cohort-plot-explain 'cardio :kind 'cohort :backend 'svg)))
        (should (eq (plist-get (plist-get plan :plot) :renderer) 'health-chart-svg-cohort)))
      (should (stringp (plist-get (health-chart-cohort-values-explain 'nope) :valid)))
      (should (stringp (plist-get (health-chart-describe-cohort-explain 'nope) :valid))))
    (let ((health-chart-source-function #'health-chart-source-cli)
          (health-chart-source-executable "biomarker")
          (health-chart-source-db nil)
          (health-chart-source-extra-args nil))
      (should (equal (plist-get (plist-get (health-chart-cohort-values-explain 'cardio :person "alex")
                                           :fetch)
                                :argv)
                     '("biomarker" "query" "--person" "alex" "--format" "json"))))))

(ert-deftest health-chart-indicator-test-cohort-values-fetch-and-enrich ()
  (health-chart-indicator-test--with-catalog
    (let* ((calls 0)
           (health-chart-source-function
            (lambda (&rest args) (cl-incf calls) (apply #'health-chart-source-static args)))
           (vs (health-chart-cohort-values 'cardio :person "alex" :as-of "2025-08-01")))
      (should (= calls 1))
      (should (equal (mapcar (lambda (v) (plist-get v :label)) vs) '("ApoB" "Lp(a)" "LDL-C")))
      (should (equal (health-chart-distinct :cohort vs) '("cardio")))
      ;; Lp(a) has no draws: its unit and bounds come from the catalog record
      (should (equal (plist-get (nth 1 vs) :unit) "nmol/L"))
      (should (equal (plist-get (nth 1 vs) :bounds) '(nil 75))))
    (let ((err (should-error (health-chart-cohort-values 'nope) :type 'health-chart-unresolvable-cohort)))
      (should (equal (plist-get (cddr err) :code) "unknown_cohort")))))

(ert-deftest health-chart-indicator-test-cohort-plot ()
  (health-chart-test-env
    (let ((health-chart-indicator-catalog-function nil))
      (health-chart-test-golden
       "cohort-metabolic.txt"
       (health-chart-cohort-plot 'metabolic :person "sam" :as-of "2025-08-01" :backend 'text))
      (should (string-prefix-p "<svg" (health-chart-cohort-plot 'overview :person "alex" :kind 'staleness
                                                                :as-of "2025-08-01" :backend 'svg)))
      (should-error (health-chart-cohort-plot 'cardio :kind 'pie) :type 'health-chart-unknown-kind))))

(ert-deftest health-chart-indicator-test-doctor-catalog-row ()
  (cl-flet ((row () (seq-find (lambda (r) (equal (plist-get r :name) "indicator-catalog"))
                              (health-chart-doctor-checks))))
    (let ((health-chart-indicator-catalog-function nil))
      (should (eq (plist-get (row) :status) 'skip)))
    (let ((health-chart-indicator-catalog-function #'health-chart-indicator-test--boom))
      (should (eq (plist-get (row) :status) 'pass)))
    (let ((health-chart-indicator-catalog-function 'health-chart-no-such-function))
      (should (eq (plist-get (row) :status) 'fail)))))

(ert-deftest health-chart-indicator-test-describe-lists-cohorts-as-json ()
  (let ((d (health-chart-describe)))
    (should (= 5 (length (plist-get d :cohorts))))
    (should (member "health.cardio.apob"
                    (append (plist-get (plist-get d :indicators) :evaluable) nil)))
    (should (stringp (json-encode d)))))

;; -----------------------------------------------------------------------
;; Dashboard
;; -----------------------------------------------------------------------

(ert-deftest health-chart-indicator-test-dashboard-cohort-selector ()
  (health-chart-test-env
    (let ((health-chart-dashboard-backend 'text)
          (health-chart-dashboard-sections nil)
          (health-chart-dashboard-cohort nil)
          (health-chart-dashboard-cohort-sections '(scorecard staleness))
          (health-chart-indicator-catalog-function nil))
      (when (get-buffer health-chart-dashboard-buffer-name)
        (kill-buffer health-chart-dashboard-buffer-name))
      (with-current-buffer (health-charts)
        (unwind-protect
            (progn
              (should (eq (lookup-key health-chart-dashboard-mode-map (kbd "C"))
                          #'health-chart-dashboard-select-cohort))
              (should-not (string-search "Indicators ·" (buffer-string)))
              (health-chart-dashboard-select-cohort "vitamins")
              (should (eq health-chart-dashboard--cohort 'vitamins))
              (should (string-search "cohort: vitamins" (buffer-string)))
              (should (string-search "Indicators · vitamins" (buffer-string)))
              (should (string-search "Days since draw · vitamins" (buffer-string)))
              (let ((buf (health-chart-dashboard-cohort-panel)))
                (unwind-protect
                    (should (string-search "Cohort · vitamins"
                                           (with-current-buffer buf (buffer-string))))
                  (kill-buffer buf)))
              (health-chart-dashboard-select-cohort "none")
              (should-not health-chart-dashboard--cohort)
              (should-not (string-search "Indicators ·" (buffer-string)))
              (should-error (health-chart-dashboard-cohort-panel) :type 'user-error)
              (should-error (health-chart-dashboard-select-cohort "nope")
                            :type 'health-chart-unresolvable-cohort)
              (should-not health-chart-dashboard--cohort))
          (kill-buffer))))))

;;; health-chart-indicator-test.el ends here
