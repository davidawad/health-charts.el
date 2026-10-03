;;; health-chart-indicator.el --- Indicator catalog, values and evaluators for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; An INDICATOR is a named, domain-generic recipe -- "latest ApoB",
;; "days since the last draw", "markers out of range" -- described by
;; an external catalog and evaluated here over canonical measurements.
;; This file is the indicator boundary; it knows nothing about where
;; the catalog lives.
;;
;;   catalog    `health-chart-indicator-catalog-function' answers
;;              (FN ID) with one catalog record and (FN nil) with every
;;              record.  nil (the default) means no catalog: indicators
;;              still evaluate from the local table below.
;;              `health-chart-indicator-catalog-static' serves
;;              `health-chart-indicator-catalog-static-data' instead.
;;   registry   `health-chart-indicator-list' / `-describe' (filtered by
;;              `health-chart-indicator-tag'); `-list-explain' and
;;              `-describe-explain' are their pure plans.
;;   evaluate   `health-chart-indicator-evaluate' ID MEASUREMENTS turns a
;;              recipe id into an INDICATOR VALUE through
;;              `health-chart-indicator-evaluators' (id -> measure) and
;;              `health-chart-indicator-measures' (measure -> function).
;;              A catalog recipe is a DAG, not elisp, so this id-keyed
;;              table is the honest boundary; extending it is a data edit.
;;   status     `health-chart-indicator-status' judges a value by its
;;              reference/optimal ranges when it has them, else by its
;;              catalog `direction' and `bounds'.
;;
;; A catalog record is the resource-catalog JSON object
;;
;;   {"ref": {"kind": "indicator", "id": "health.cardio.apob"},
;;    "name": "...", "revision": "1.0.0",
;;    "attributes": {"description": "...", "owner": "...", "tags": [...],
;;                   "parameters": {...},
;;                   "value": {"type", "unit", "scale",
;;                             "bounds": {"min", "max"}},
;;                   "semantics": {"measure", "subject": {"kind", "key"},
;;                                 "time_basis", "direction"},
;;                   "recipe": {...}}}
;;
;; as an alist, hash table or plist.  Its member names live only in
;; `health-chart-indicator-record-paths'; everything else reads the
;; canonical record plist `health-chart-indicator-normalize-record'
;; returns.
;;
;; An INDICATOR VALUE -- what the indicator chart kinds draw -- is the
;; canonical plist
;;
;;   (:id "health.cardio.apob" :label "ApoB" :cohort "cardio" :value 84
;;    :unit "mg/dL" :date "2025-06-02" :as-of "2025-08-01"
;;    :series (104 99 91 86 93 84) :direction lower-better :bounds (nil 90)
;;    :ref-low 0 :ref-high 90 :opt-low nil :opt-high 80 :marker "apob"
;;    :person "alex" :measure latest :status nil)
;;
;; from `health-chart-indicator-normalize-value', which also reads
;; alists and JSON objects with the same (snake_case) members.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)

(define-error 'health-chart-indicator-error
  "health-chart: indicator problem" 'health-chart-error)
(define-error 'health-chart-unknown-indicator
  "health-chart: unknown indicator" 'health-chart-indicator-error)
(define-error 'health-chart-catalog-error
  "health-chart: indicator catalog failed" 'health-chart-indicator-error)

;; -----------------------------------------------------------------------
;; Configuration
;; -----------------------------------------------------------------------

(defcustom health-chart-indicator-catalog-function nil
  "Function answering indicator catalog lookups, or nil for no catalog.
Called as (FN RECIPE-ID) it returns that indicator's catalog record, or
nil when the catalog has no such id; called as (FN nil) it returns every
record (a list, or an object whose `records', `items' or `data' member
holds them), or nil when it cannot list -- then listing probes each
locally known id instead.  A record is an alist, hash table or plist in
the resource-catalog shape (see the Commentary of
health-chart-indicator.el).  Without a catalog, indicators evaluate from
`health-chart-indicator-evaluators' alone.
`health-chart-indicator-catalog-static' serves
`health-chart-indicator-catalog-static-data'."
  :type '(choice (const :tag "No catalog" nil)
                 (function-item health-chart-indicator-catalog-static)
                 function)
  :group 'health-charts)

(defvar health-chart-indicator-catalog-static-data nil
  "Catalog records `health-chart-indicator-catalog-static' serves.")

(defcustom health-chart-indicator-tag "health"
  "Tag `health-chart-indicator-list' keeps by default, or nil for every record."
  :type '(choice (const :tag "Every record" nil) string)
  :group 'health-charts)

(defcustom health-chart-indicator-due-days 120
  "Days since a draw after which an indicator is due for a re-test."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-indicator-stale-days 365
  "Days since a draw after which an indicator is stale."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-indicator-evaluators
  '(("health.biomarker.latest" :measure latest)
    ("health.biomarker.series" :measure series)
    ("health.biomarker.status" :measure status)
    ("health.biomarker.range-position" :measure range-position)
    ("health.biomarker.trend-slope" :measure trend-slope)
    ("health.biomarker.days-since-draw" :measure days-since-draw)
    ("health.panel.out-of-range-count" :measure out-of-range-count)
    ("health.cardio.apob" :measure latest :marker "apob" :direction lower-better)
    ("health.cardio.lp-a" :measure latest :marker ("lpa" "lp_a") :direction lower-better)
    ("health.metabolic.hba1c" :measure latest :marker "hba1c" :direction lower-better)
    ("health.inflammation.hs-crp" :measure latest :marker ("hs_crp" "crp")
     :direction lower-better)
    ("health.vitamin-d" :measure latest :marker ("vitamin_d" "vitamin_d_25oh")
     :direction in-range))
  "Local evaluator for each catalog RECIPE-ID.
Each entry is (RECIPE-ID :measure MEASURE [:marker M] [:label L]
[:direction D] [:bounds (LO HI)] [:unit U]).  MEASURE names an entry of
`health-chart-indicator-measures'.  :marker is a marker id, or a list of
candidate ids of which the first present in the data wins; a member's
:params (:marker M) overrides it.  A recipe id absent from this table
cannot be evaluated -- it is reported, never dropped.  Supporting a new
recipe is a data edit: add one entry."
  :type '(alist :key-type string :value-type plist)
  :group 'health-charts)

(defvar health-chart-indicator-measures
  '((latest :fn health-chart-indicator--measure-latest :scope marker
            :direction in-range
            :doc "The newest draw's value, judged by its ranges.")
    (series :fn health-chart-indicator--measure-latest :scope marker
            :direction in-range
            :doc "Every draw of a marker, oldest first; the value is the newest.")
    (status :fn health-chart-indicator--measure-latest :scope marker
            :direction in-range
            :doc "The newest draw's status against its reference and optimal ranges.")
    (range-position :fn health-chart-indicator--measure-range-position :scope marker
                    :direction in-range :bounds (0 1) :unit "of range"
                    :doc "Where the newest draw sits in its reference range: 0 low edge, 1 high edge.")
    (trend-slope :fn health-chart-indicator--measure-trend-slope :scope marker
                 :direction neutral
                 :doc "Least-squares slope of a marker's draws, in its unit per year.")
    (days-since-draw :fn health-chart-indicator--measure-days-since :scope either
                     :direction lower-better :unit "days"
                     :doc "Days from the newest draw (of a marker, or of any) to the as-of date.")
    (out-of-range-count :fn health-chart-indicator--measure-out-of-range :scope panel
                        :direction lower-better :bounds (0 0) :unit "markers"
                        :doc "Markers whose newest draw is outside its reference range."))
  "Measures: (MEASURE :fn FN :scope SCOPE :doc DOC [:direction :bounds :unit]).
FN is called with the person's canonical measurements (one marker's,
oldest first, when SCOPE is `marker') and a context plist (:all :marker
:as-of :params); it returns a partial indicator value plist (:value
:unit :date :series and any range keys).  SCOPE `marker' needs a marker,
`panel' ignores one, `either' takes one when given.  The other keys are
defaults a catalog record or evaluator entry overrides.")

(defconst health-chart-indicator-directions
  '(lower-better higher-better in-range neutral)
  "Every canonical indicator direction.")

;; -----------------------------------------------------------------------
;; Reading JSON-ish objects
;; -----------------------------------------------------------------------

(defun health-chart-indicator--nil (v)
  "V, with JSON null and false read as nil."
  (unless (memq v '(:null :json-null :json-false :false)) v))

(defun health-chart-indicator--member (object key)
  "Member KEY (a symbol) of OBJECT: an alist, hash table or plist.
Alists may use symbol or string keys and plists keywords; a hyphen in
KEY also matches an underscore."
  (let ((names (delete-dups (list (symbol-name key)
                                  (replace-regexp-in-string "-" "_" (symbol-name key))
                                  (replace-regexp-in-string "_" "-" (symbol-name key))))))
    (health-chart-indicator--nil
     (cond
      ((hash-table-p object)
       (seq-some (lambda (n) (or (gethash n object) (gethash (intern n) object))) names))
      ((and (consp object) (keywordp (car object)))
       (seq-some (lambda (n) (plist-get object (intern (concat ":" n)))) names))
      ((and (consp object) (consp (car object)))
       (seq-some (lambda (n) (or (cdr (assq (intern n) object)) (cdr (assoc n object))))
                 names))))))

(defun health-chart-indicator--path (object path)
  "The member of OBJECT reached by PATH, a list of member symbols."
  (dolist (key path object)
    (setq object (and object (health-chart-indicator--member object key)))))

(defun health-chart-indicator--list (v)
  "V (a list, vector or nil) as a list; a lone string as a one-element list."
  (cond ((null v) nil)
        ((stringp v) (list v))
        ((or (listp v) (vectorp v)) (mapcar #'health-chart-indicator--nil (append v nil)))
        (t (list v))))

(defun health-chart-indicator--string (v)
  "V as a string, or nil."
  (setq v (health-chart-indicator--nil v))
  (cond ((null v) nil)
        ((stringp v) v)
        ((symbolp v) (symbol-name v))
        (t (format "%s" v))))

(defun health-chart-indicator--symbol (v)
  "V as a lower-case symbol, or nil."
  (when-let* ((s (health-chart-indicator--string v)))
    (unless (string-empty-p (string-trim s))
      (intern (downcase (replace-regexp-in-string "_" "-" (string-trim s)))))))

(defun health-chart-indicator-direction (direction)
  "DIRECTION (string or symbol, any spelling) as a canonical symbol.
One of `health-chart-indicator-directions', or nil when absent."
  (when-let* ((s (health-chart-indicator--symbol direction)))
    (pcase (replace-regexp-in-string "[ ]" "-" (symbol-name s))
      ((or "lower-better" "lower-is-better" "lower" "down" "decrease" "minimize"
           "less-is-better" "smaller-is-better")
       'lower-better)
      ((or "higher-better" "higher-is-better" "higher" "up" "increase" "maximize"
           "more-is-better" "larger-is-better")
       'higher-better)
      ((or "in-range" "target" "target-range" "range" "within" "within-range" "band")
       'in-range)
      (_ 'neutral))))

(defun health-chart-indicator-bounds (bounds)
  "BOUNDS in any accepted form as (LO HI), either possibly nil, or nil.
Accepts an object with min/max (or low/high), a two-element list or
vector, or a (LO . HI) cons."
  (setq bounds (health-chart-indicator--nil bounds))
  (let ((pair
         (cond
          ((null bounds) nil)
          ((or (hash-table-p bounds) (and (consp bounds) (consp (car bounds)))
               (and (consp bounds) (keywordp (car bounds))
                    (health-chart-indicator--nil (car bounds))))
           (list (or (health-chart-indicator--member bounds 'min)
                     (health-chart-indicator--member bounds 'low))
                 (or (health-chart-indicator--member bounds 'max)
                     (health-chart-indicator--member bounds 'high))))
          ((vectorp bounds) (append bounds nil))
          ((and (consp bounds) (not (listp (cdr bounds)))) (list (car bounds) (cdr bounds)))
          ((consp bounds) (list (car bounds) (cadr bounds))))))
    (setq pair (mapcar #'health-chart-indicator--nil pair))
    (when (or (car pair) (cadr pair))
      (list (car pair) (cadr pair)))))

;; -----------------------------------------------------------------------
;; Catalog records
;; -----------------------------------------------------------------------

(defconst health-chart-indicator-record-paths
  '((:id ref id) (:kind ref kind) (:name name) (:revision revision)
    (:description attributes description) (:owner attributes owner)
    (:tags attributes tags) (:parameters attributes parameters)
    (:value-type attributes value type) (:unit attributes value unit)
    (:scale attributes value scale) (:bounds attributes value bounds)
    (:measure attributes semantics measure)
    (:subject-kind attributes semantics subject kind)
    (:subject-key attributes semantics subject key)
    (:time-basis attributes semantics time_basis)
    (:direction attributes semantics direction)
    (:recipe attributes recipe))
  "Canonical record key -> member path in a resource-catalog record.
The only place that knows the catalog's member names.")

(defconst health-chart-indicator-record-list-keys '(records items data)
  "Members of a catalog listing object that may hold the record list.")

(defun health-chart-indicator-normalize-record (record)
  "Catalog RECORD (alist, hash table or plist) as a canonical plist.
Keys follow `health-chart-indicator-record-paths'; :tags is a list of
strings, :bounds (LO HI) or nil, :direction canonical, :recipe-p
whether the record carries a recipe.  A canonical plist passes through."
  (if (and (consp record) (eq (car record) :id) (plist-member record :recipe-p))
      record
    (let ((get (lambda (key) (health-chart-indicator--path
                              record (alist-get key health-chart-indicator-record-paths)))))
      (list :id (health-chart-indicator--string (funcall get :id))
            :kind (health-chart-indicator--string (funcall get :kind))
            :name (health-chart-indicator--string (funcall get :name))
            :revision (health-chart-indicator--string (funcall get :revision))
            :description (health-chart-indicator--string (funcall get :description))
            :owner (health-chart-indicator--string (funcall get :owner))
            :tags (mapcar #'health-chart-indicator--string
                          (health-chart-indicator--list (funcall get :tags)))
            :parameters (funcall get :parameters)
            :value-type (health-chart-indicator--string (funcall get :value-type))
            :unit (health-chart-indicator--string (funcall get :unit))
            :scale (health-chart-indicator--string (funcall get :scale))
            :bounds (health-chart-indicator-bounds (funcall get :bounds))
            :measure (health-chart-indicator--string (funcall get :measure))
            :subject-kind (health-chart-indicator--string (funcall get :subject-kind))
            :subject-key (health-chart-indicator--string (funcall get :subject-key))
            :time-basis (health-chart-indicator--string (funcall get :time-basis))
            :direction (health-chart-indicator-direction (funcall get :direction))
            :recipe-p (and (funcall get :recipe) t)))))

(defun health-chart-indicator-catalog-static (id)
  "Answer catalog lookup ID from `health-chart-indicator-catalog-static-data'.
ID nil returns every record; a recipe id string returns its record or nil."
  (let ((records (health-chart-indicator--records
                  health-chart-indicator-catalog-static-data)))
    (if (null id)
        records
      (seq-find (lambda (r) (equal id (health-chart-indicator--path r '(ref id))))
                records))))

(defun health-chart-indicator--records (data)
  "The record list in DATA, a list, vector or listing object."
  (setq data (health-chart-indicator--nil data))
  (cond
   ((null data) nil)
   ((vectorp data) (append data nil))
   ((or (hash-table-p data)
        (and (consp data) (consp (car data)) (symbolp (caar data))
             (not (assq 'ref data))))
    (health-chart-indicator--list
     (seq-some (lambda (k) (health-chart-indicator--member data k))
               health-chart-indicator-record-list-keys)))
   ((and (consp data) (keywordp (car data))) (list data))
   (t data)))

(defun health-chart-indicator--call-catalog (id)
  "Call `health-chart-indicator-catalog-function' with ID.
Signal `health-chart-catalog-error' when it is unset or fails."
  (unless health-chart-indicator-catalog-function
    (signal 'health-chart-catalog-error
            (list "no indicator catalog; set `health-chart-indicator-catalog-function' \
\(or use `health-chart-indicator-catalog-static')"
                  :code "catalog_missing")))
  (condition-case err
      (funcall health-chart-indicator-catalog-function id)
    (health-chart-error (signal (car err) (cdr err)))
    (error
     (signal 'health-chart-catalog-error
             (list (format "indicator catalog %s failed on %S: %s; fix it or \
set `health-chart-indicator-catalog-function' to nil"
                           health-chart-indicator-catalog-function id
                           (error-message-string err))
                   :code "catalog_failed")))))

(defun health-chart-indicator-known-ids ()
  "Recipe ids this package can evaluate.
In `health-chart-indicator-evaluators' order."
  (mapcar #'car health-chart-indicator-evaluators))

(defun health-chart-indicator-catalog-get (id)
  "The canonical catalog record of recipe ID, or nil when the catalog lacks it.
Calls `health-chart-indicator-catalog-function'; signals
`health-chart-catalog-error' when there is none or it fails."
  (when-let* ((record (health-chart-indicator--call-catalog id)))
    (health-chart-indicator-normalize-record record)))

(defun health-chart-indicator--tag-p (record tag)
  "Non-nil when canonical RECORD carries TAG (or TAG is nil)."
  (or (null tag) (member tag (plist-get record :tags))))

(defun health-chart-indicator--list-tag (args)
  "The tag filter ARGS select: :tag when given (even nil), else the default."
  (if (plist-member args :tag) (plist-get args :tag) health-chart-indicator-tag))

(defun health-chart-indicator-list (&rest args)
  "Every catalog record as a canonical plist, filtered by tag.
ARGS: :tag (default `health-chart-indicator-tag'; pass :tag nil
explicitly for every record).  Calls
`health-chart-indicator-catalog-function' with nil; when that returns
nothing or fails, probes each id of `health-chart-indicator-evaluators'
\(a failing probe signals `health-chart-catalog-error').  See
`health-chart-indicator-list-explain' for the plan without the calls."
  (let* ((tag (health-chart-indicator--list-tag args))
         (records (health-chart-indicator--records
                   (condition-case err (health-chart-indicator--call-catalog nil)
                     ;; a lookup-only catalog may reject nil: probe instead
                     (health-chart-catalog-error
                      (if (equal (plist-get (cddr err) :code) "catalog_failed") nil
                        (signal (car err) (cdr err))))))))
    (unless records
      (setq records (delq nil (mapcar #'health-chart-indicator--call-catalog
                                      (health-chart-indicator-known-ids)))))
    (seq-filter (lambda (r) (health-chart-indicator--tag-p r tag))
                (mapcar #'health-chart-indicator-normalize-record records))))

(defun health-chart-indicator-list-explain (&rest args)
  "The plan `health-chart-indicator-list' follows for ARGS.  Pure.
A plist: :function (the catalog function or nil) :configured :tag
:calls (each (FUNCTION ARG) it would make) :fallback (the ids probed
when the listing call returns nothing) :error (why it would fail)."
  (let ((fn health-chart-indicator-catalog-function))
    (list :function fn :configured (and fn t)
          :tag (health-chart-indicator--list-tag args)
          :calls (when fn (list (list fn nil)))
          :fallback (when fn (mapcar (lambda (id) (list fn id))
                                     (health-chart-indicator-known-ids)))
          :error (unless fn "no indicator catalog; set \
`health-chart-indicator-catalog-function'"))))

(defun health-chart-indicator--evaluator (id)
  "ID's entry plist in `health-chart-indicator-evaluators', or nil."
  (cdr (assoc id health-chart-indicator-evaluators)))

(defun health-chart-indicator--local (id)
  "What this package knows about recipe ID without a catalog."
  (let* ((evaluator (health-chart-indicator--evaluator id))
         (measure (plist-get evaluator :measure)))
    (list :evaluable (and evaluator (assq measure health-chart-indicator-measures) t)
          :evaluator evaluator
          :measure-doc (plist-get (cdr (assq measure health-chart-indicator-measures)) :doc))))

(defun health-chart-indicator-describe (id)
  "Describe recipe ID: its catalog record and its local evaluator.
A plist (:id :record RECORD-OR-NIL :in-catalog BOOL :evaluable BOOL
:evaluator ENTRY :measure-doc DOC).  Calls the catalog when one is set;
with none, :record is nil and :in-catalog `unknown'.  See
`health-chart-indicator-describe-explain' for the plan."
  (let ((record (and health-chart-indicator-catalog-function
                     (health-chart-indicator-catalog-get id))))
    (append (list :id id :record record
                  :in-catalog (if health-chart-indicator-catalog-function (and record t) 'unknown))
            (health-chart-indicator--local id))))

(defun health-chart-indicator-describe-explain (id)
  "The plan `health-chart-indicator-describe' follows for ID.  Pure.
A plist: :id :calls (the catalog call it would make, if any) plus the
local evaluator facts (:evaluable :evaluator :measure-doc)."
  (append (list :id id
                :calls (when health-chart-indicator-catalog-function
                         (list (list health-chart-indicator-catalog-function id))))
          (health-chart-indicator--local id)))

;; -----------------------------------------------------------------------
;; Indicator values
;; -----------------------------------------------------------------------

(defconst health-chart-indicator-value-keys
  '(:id :label :cohort :value :unit :date :as-of :series :direction :bounds
        :ref-low :ref-high :opt-low :opt-high :marker :person :measure :status)
  "Keys of a canonical indicator value, in order.")

(defun health-chart-indicator--value-of (key v)
  "Canonical form of member V for indicator value KEY."
  (setq v (health-chart-indicator--nil v))
  (pcase key
    ((or :id :label :cohort :unit :marker :person) (health-chart-indicator--string v))
    ((or :date :as-of) (let ((s (health-chart-indicator--string v)))
                         (if (health-chart-date-p s) (substring s 0 10) s)))
    (:series (health-chart-indicator--list v))
    (:direction (health-chart-indicator-direction v))
    (:bounds (health-chart-indicator-bounds v))
    ((or :measure :status) (health-chart-indicator--symbol v))
    (_ v)))

(defun health-chart-indicator-normalize-value (v)
  "Indicator value V (plist, alist or hash table) as a canonical plist.
Keys appear in `health-chart-indicator-value-keys' order; absent ones are
nil.  `name' is read as :label when there is no label.  Idempotent."
  (unless (or (hash-table-p v) (consp v))
    (signal 'health-chart-indicator-error
            (list (format "an indicator value must be a plist, alist or object, got %S" v)
                  :code "invalid_data")))
  (cl-loop for key in health-chart-indicator-value-keys
           for raw = (health-chart-indicator--member v (intern (substring (symbol-name key) 1)))
           for raw2 = (if (and (eq key :label) (null raw))
                          (health-chart-indicator--member v 'name)
                        raw)
           append (list key (health-chart-indicator--value-of key raw2))))

(defconst health-chart-indicator-value-list-keys '(values indicators items data)
  "Envelope members that may hold a list of indicator values, in order.")

(defun health-chart-indicator-normalize-values (data)
  "DATA (a list or vector of indicator values) as canonical plists.
An envelope object whose `values' (or `indicators', `items', `data')
member holds the list is unwrapped."
  (when (or (hash-table-p data)
            (and (consp data) (consp (car data)) (symbolp (caar data))
                 (cl-some (lambda (k) (assq k data)) health-chart-indicator-value-list-keys)))
    (setq data (cl-some (lambda (k) (health-chart-indicator--member data k))
                        health-chart-indicator-value-list-keys)))
  (mapcar #'health-chart-indicator-normalize-value (append data nil)))

(defun health-chart-indicator-validate-values (data)
  "Signal `health-chart-error' with :index unless DATA are valid indicator values.
DATA is already normalized."
  (unless (listp data)
    (signal 'health-chart-error
            (list (format "indicator values must be a list, got %S" data) :code "invalid_data")))
  (cl-loop
   for v in data for i from 0
   do (cl-flet ((bad (fmt &rest args)
                  (signal 'health-chart-error
                          (list (format "element %d: %s" i (apply #'format fmt args))
                                :code "invalid_data" :index i))))
        (unless (or (plist-get v :id) (plist-get v :label))
          (bad "needs an \"id\" or a \"label\""))
        (unless (or (null (plist-get v :value)) (numberp (plist-get v :value)))
          (bad "\"value\" must be a number or null, got %S" (plist-get v :value)))
        (dolist (key '(:date :as-of))
          (let ((d (plist-get v key)))
            (unless (or (null d) (health-chart-date-p d))
              (bad "%s must be YYYY-MM-DD or null, got %S" key d))))
        (unless (cl-every #'numberp (plist-get v :series))
          (bad "\"series\" must be numbers, oldest first, got %S" (plist-get v :series)))
        (dolist (key '(:ref-low :ref-high :opt-low :opt-high))
          (unless (or (null (plist-get v key)) (numberp (plist-get v key)))
            (bad "%s must be a number or null, got %S" key (plist-get v key))))
        (pcase-let ((`(,lo ,hi) (plist-get v :bounds)))
          (unless (and (or (null lo) (numberp lo)) (or (null hi) (numberp hi)))
            (bad "\"bounds\" must be numbers, got %S" (plist-get v :bounds)))
          (when (and lo hi (> lo hi))
            (bad "bounds min %s exceeds max %s (swap them)" lo hi)))
        (when-let* ((s (plist-get v :status)))
          (unless (memq s health-chart-statuses)
            (bad "\"status\" must be one of %s, got %S"
                 (mapconcat #'symbol-name health-chart-statuses ", ") s))))))

(defun health-chart-indicator-has-ranges-p (v)
  "Non-nil when indicator value V carries reference or optimal bounds."
  (or (plist-get v :ref-low) (plist-get v :ref-high)
      (plist-get v :opt-low) (plist-get v :opt-high)))

(defun health-chart-indicator-status (v)
  "Status of indicator value V, one of `health-chart-statuses'.
An explicit :status wins.  Otherwise a value with reference or optimal
bounds is judged like a measurement (`health-chart-status').  Otherwise
its :bounds (LO HI) and :direction decide: `lower-better' is high above
HI, optimal below LO, else normal; `higher-better' is low below LO,
optimal above HI, else normal; any other direction is low below LO,
high above HI, else normal.  No number, or nothing to judge by, is
unknown."
  (let ((x (plist-get v :value))
        (bounds (plist-get v :bounds)))
    (cond
     ((memq (plist-get v :status) health-chart-statuses) (plist-get v :status))
     ((not (numberp x)) 'unknown)
     ((health-chart-indicator-has-ranges-p v)
      (health-chart-status (list :value x
                                 :ref-low (plist-get v :ref-low) :ref-high (plist-get v :ref-high)
                                 :opt-low (plist-get v :opt-low) :opt-high (plist-get v :opt-high))))
     (bounds
      (pcase-let ((`(,lo ,hi) bounds))
        (pcase (plist-get v :direction)
          ('lower-better (cond ((and hi (> x hi)) 'high) ((and lo (< x lo)) 'optimal) (t 'normal)))
          ('higher-better (cond ((and lo (< x lo)) 'low) ((and hi (> x hi)) 'optimal) (t 'normal)))
          (_ (cond ((and lo (< x lo)) 'low) ((and hi (> x hi)) 'high) (t 'normal))))))
     (t 'unknown))))

(defun health-chart-indicator--target (v)
  "The (LO . HI) band indicator value V aims for, or nil.
The optimal range, else the reference range, else :bounds."
  (cond
   ((or (plist-get v :opt-low) (plist-get v :opt-high))
    (cons (plist-get v :opt-low) (plist-get v :opt-high)))
   ((or (plist-get v :ref-low) (plist-get v :ref-high))
    (cons (plist-get v :ref-low) (plist-get v :ref-high)))
   ((plist-get v :bounds)
    (cons (car (plist-get v :bounds)) (cadr (plist-get v :bounds))))))

(defun health-chart-indicator-trend (v)
  "Trend verdict of indicator value V's :series, oldest to newest.
improved or worsened by :direction (`in-range' compares the distance
outside the target band), on-target when both ends are in it, steady
when the change is under 1%, rising or falling when the direction is
neutral, nil with fewer than two numbers."
  (let ((series (seq-filter #'numberp (plist-get v :series))))
    (when (cdr series)
      (let* ((a (car series)) (b (car (last series)))
             (eps (* 0.01 (max (abs a) (abs b) 1e-9)))
             (target (health-chart-indicator--target v)))
        (pcase (plist-get v :direction)
          ('lower-better (cond ((< b (- a eps)) 'improved) ((> b (+ a eps)) 'worsened) (t 'steady)))
          ('higher-better (cond ((> b (+ a eps)) 'improved) ((< b (- a eps)) 'worsened) (t 'steady)))
          ((and (or 'in-range 'nil) (guard target))
           (let ((da (health-chart--outside a (car target) (cdr target)))
                 (db (health-chart--outside b (car target) (cdr target))))
             (cond ((< db (- da eps)) 'improved) ((> db (+ da eps)) 'worsened)
                   ((zerop db) 'on-target) (t 'steady))))
          (_ (cond ((> b (+ a eps)) 'rising) ((< b (- a eps)) 'falling) (t 'steady))))))))

(defun health-chart-indicator-trend-label (verdict series)
  "Arrow and word for trend VERDICT of SERIES, e.g. \"↘ improved\", or \"\"."
  (if (null verdict) ""
    (let* ((nums (seq-filter #'numberp series))
           (a (car nums)) (b (car (last nums))))
      (format "%s %s" (cond ((memq verdict '(steady on-target)) "→")
                            ((> b a) "↗") ((< b a) "↘") (t "→"))
              verdict))))

;; -----------------------------------------------------------------------
;; Freshness of a draw
;; -----------------------------------------------------------------------

(defcustom health-chart-staleness-glyphs
  '((fresh . "●") (due . "◐") (stale . "▲") (undated . "?"))
  "Glyph for each draw freshness state, used beside every state word."
  :type '(alist :key-type symbol :value-type string)
  :group 'health-charts)

(defun health-chart-staleness-label (state)
  "Glyph and word for freshness STATE, e.g. \"▲ stale\"."
  (format "%s %s" (or (alist-get state health-chart-staleness-glyphs) "?") state))

(defun health-chart-staleness-face (state)
  "Face for freshness STATE."
  (pcase state
    ('fresh 'health-chart-optimal)
    ('due 'health-chart-suboptimal)
    ('stale 'health-chart-out-of-range)
    (_ 'health-chart-dim)))

(defun health-chart-trend-face (verdict)
  "Face for trend VERDICT."
  (pcase verdict
    ('improved 'health-chart-improved)
    ('worsened 'health-chart-worsened)
    (_ 'health-chart-dim)))

;; -----------------------------------------------------------------------
;; Measures
;; -----------------------------------------------------------------------

(defun health-chart-indicator--today ()
  "Today's local date as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"))

(defun health-chart-indicator--measure-latest (ms &rest _context)
  "The newest of one marker's MS with its ranges and every value as :series."
  (when-let* ((latest (car (last ms))))
    (list :value (plist-get latest :value) :unit (plist-get latest :unit)
          :date (plist-get latest :date)
          :series (delq nil (mapcar (lambda (m) (plist-get m :value)) ms))
          :ref-low (plist-get latest :ref-low) :ref-high (plist-get latest :ref-high)
          :opt-low (plist-get latest :opt-low) :opt-high (plist-get latest :opt-high))))

(defun health-chart-indicator--measure-range-position (ms &rest _context)
  "Where each of one marker's MS sits in the newest reference range.
0 is the low edge, 1 the high edge; a range with only a high edge
starts at 0.  Nil value when there is no usable range."
  (when-let* ((latest (car (last ms))))
    (let* ((lo (or (plist-get latest :ref-low) (and (plist-get latest :ref-high) 0)))
           (hi (plist-get latest :ref-high))
           (pos (lambda (m) (and lo hi (> hi lo) (numberp (plist-get m :value))
                                 (/ (round (* 1000 (/ (- (plist-get m :value) lo)
                                                      (float (- hi lo)))))
                                    1000.0)))))
      (list :value (funcall pos latest) :date (plist-get latest :date)
            :series (delq nil (mapcar pos ms))))))

(defun health-chart-indicator--slope (points)
  "Least-squares slope of POINTS, a list of (X . Y), or nil."
  (let* ((n (length points)))
    (when (> n 1)
      (let* ((mx (/ (apply #'+ (mapcar #'car points)) (float n)))
             (my (/ (apply #'+ (mapcar #'cdr points)) (float n)))
             (sxx (apply #'+ (mapcar (lambda (p) (expt (- (car p) mx) 2)) points)))
             (sxy (apply #'+ (mapcar (lambda (p) (* (- (car p) mx) (- (cdr p) my))) points))))
        (unless (zerop sxx) (/ sxy sxx))))))

(defun health-chart-indicator--measure-trend-slope (ms &rest _context)
  "Least-squares slope of one marker's MS, in its unit per year."
  (when-let* ((latest (car (last ms))))
    (let ((slope (health-chart-indicator--slope
                  (mapcar (lambda (m) (cons (health-chart-date-days (plist-get m :date))
                                            (plist-get m :value)))
                          ms))))
      (list :value (and slope (/ (round (* 1000 slope 365.25)) 1000.0))
            :unit (when (plist-get latest :unit) (format "%s/yr" (plist-get latest :unit)))
            :date (plist-get latest :date)
            :series (delq nil (mapcar (lambda (m) (plist-get m :value)) ms))))))

(defun health-chart-indicator--measure-days-since (ms &rest context)
  "Days from the newest draw in MS to CONTEXT's :as-of date."
  (when-let* ((date (car (last (health-chart-dates ms)))))
    (list :value (- (health-chart-date-days (plist-get context :as-of))
                    (health-chart-date-days date))
          :date date)))

(defun health-chart-indicator--measure-out-of-range (ms &rest _context)
  "Markers of MS whose newest draw is out of range; :series per draw date."
  (let ((dates (health-chart-dates ms))
        (count (lambda (sub) (seq-count #'health-chart-out-of-range-p (health-chart-latest sub)))))
    (when dates
      (list :value (funcall count ms) :date (car (last dates))
            :series (mapcar (lambda (d) (funcall count (health-chart-filter ms :until d)))
                            dates)))))

;; -----------------------------------------------------------------------
;; Evaluation
;; -----------------------------------------------------------------------

(defun health-chart-indicator--plist-drop (plist &rest keys)
  "PLIST without KEYS."
  (cl-loop for (k v) on plist by #'cddr
           unless (memq k keys) append (list k v)))

(defun health-chart-indicator-plan (id &rest params)
  "The pure evaluation plan for recipe ID with PARAMS, or signal.
PARAMS may carry :marker (an id or candidate list) :label :direction
:bounds :unit.  Returns (:id :measure :scope :markers CANDIDATES :params
PARAMS).  Signals `health-chart-unknown-indicator' when ID has no
evaluator, its measure is unknown, or a marker measure has no marker."
  (let* ((evaluator (or (health-chart-indicator--evaluator id)
                        (signal 'health-chart-unknown-indicator
                                (list (format "no local evaluator for indicator %S; add an entry \
to `health-chart-indicator-evaluators' or drop it" id)
                                      :code "unknown_indicator" :id id))))
         (measure (plist-get evaluator :measure))
         (spec (or (cdr (assq measure health-chart-indicator-measures))
                   (signal 'health-chart-unknown-indicator
                           (list (format "indicator %S uses unknown measure %S; use one of %s" id measure
                                         (mapconcat (lambda (m) (symbol-name (car m)))
                                                    health-chart-indicator-measures ", "))
                                 :code "unknown_measure" :id id))))
         (scope (plist-get spec :scope))
         (markers (health-chart-indicator--list (or (plist-get params :marker)
                                                    (plist-get evaluator :marker)))))
    (when (and (eq scope 'marker) (null markers))
      (signal 'health-chart-unknown-indicator
              (list (format "indicator %S measures one marker; give it :params (:marker \"ldl_c\")" id)
                    :code "missing_marker" :id id)))
    (list :id id :measure measure :scope scope
          :markers (unless (eq scope 'panel) markers) :params params)))

(defun health-chart-indicator--label (plan marker)
  "Default label of evaluation PLAN for MARKER."
  (let ((m (and marker (health-chart-marker-label marker))))
    (pcase (plist-get plan :measure)
      ('range-position (format "%s position" m))
      ('trend-slope (format "%s slope" m))
      ('days-since-draw (if m (format "%s age" m) "Days since draw"))
      ('out-of-range-count "Out of range")
      (_ m))))

(defun health-chart-indicator-evaluate (id ms &rest params)
  "Evaluate recipe ID over canonical measurements MS; return an indicator value.
PARAMS: :marker (overrides the evaluator's), :person (default the first
in MS), :as-of (default today; days are counted to it), :label
:direction :bounds :unit (override the defaults), :record (a canonical
catalog record whose direction, bounds, unit and subject key fill in
what PARAMS leave out) and :cohort.  Pure: no catalog or source call.
A marker absent from MS gives a nil :value, which draws as n/a."
  (let* ((record (plist-get params :record))
         (params (if (and record (null (plist-get params :marker))
                          (null (plist-get (health-chart-indicator--evaluator id) :marker))
                          (equal (plist-get record :subject-kind) "biomarker")
                          (plist-get record :subject-key))
                     (append (list :marker (plist-get record :subject-key)) params)
                   params))
         (plan (apply #'health-chart-indicator-plan id params))
         (evaluator (health-chart-indicator--evaluator id))
         (spec (cdr (assq (plist-get plan :measure) health-chart-indicator-measures)))
         (as-of (or (plist-get params :as-of) (health-chart-indicator--today)))
         (person (or (plist-get params :person) (car (health-chart-persons ms))))
         (mine (health-chart-fill-ranges (health-chart-filter ms :person person)))
         (candidates (plist-get plan :markers))
         (marker (or (seq-find (lambda (c) (health-chart-filter mine :marker c)) candidates)
                     (car candidates)))
         (scoped (health-chart-sort-by-date
                  (if marker (health-chart-filter mine :marker marker) mine)))
         (result (when scoped
                   (funcall (plist-get spec :fn) scoped :all mine :marker marker :as-of as-of
                            :params params)))
         (pick (lambda (key)
                 (cl-some (lambda (source) (plist-get source key))
                          (list params record evaluator spec)))))
    (health-chart-indicator-normalize-value
     (append
      (list :id id
            :label (or (plist-get params :label) (plist-get evaluator :label)
                       (health-chart-indicator--label plan marker))
            :cohort (plist-get params :cohort)
            :unit (or (plist-get params :unit) (plist-get result :unit)
                      (plist-get evaluator :unit) (plist-get spec :unit)
                      (plist-get record :unit))
            :as-of as-of
            :direction (funcall pick :direction)
            :bounds (or (funcall pick :bounds)
                        (and (eq (plist-get plan :measure) 'days-since-draw)
                             (list 0 health-chart-indicator-stale-days)))
            :marker marker :person person :measure (plist-get plan :measure))
      (health-chart-indicator--plist-drop result :unit)))))

(provide 'health-chart-indicator)
;;; health-chart-indicator.el ends here
