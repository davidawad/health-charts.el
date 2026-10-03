;;; health-chart-cohort.el --- Named indicator cohorts for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A COHORT is DATA: one `health-chart-indicator-cohorts' entry names a
;; reusable set of catalog indicators -- cardio, metabolic,
;; inflammation, vitamins.  Adding a cohort or a member is a data edit,
;; no new code.
;;
;;   pure       `health-chart-list-cohorts' (summary per cohort),
;;              `health-chart-resolve-cohort' (members -> evaluation
;;              plans, or a typed error), `health-chart-cohort-evaluate'
;;              (a cohort over measurements you already hold).
;;   effectful  `health-chart-describe-cohort' (probes the catalog for
;;              every member), `health-chart-cohort-values' (fetches
;;              through `health-chart-source-function', evaluates),
;;              `health-chart-cohort-plot' (values -> a chart kind).
;;   plans      each effectful call has a pure `-explain' twin naming
;;              the exact calls it would make, and making none.
;;   health     `health-chart-cohort-doctor-checks', one row per cohort
;;              plus the catalog and the evaluator table.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-indicator)
(require 'health-chart-plot)

(define-error 'health-chart-unresolvable-cohort
  "health-chart: cohort cannot be resolved" 'health-chart-indicator-error)

(defcustom health-chart-indicator-cohorts
  '((cardio
     :doc "Atherogenic lipoproteins: ApoB, Lp(a) and LDL-C."
     :members ((:indicator "health.cardio.apob")
               (:indicator "health.cardio.lp-a")
               (:indicator "health.biomarker.latest" :params (:marker "ldl_c"))))
    (metabolic
     :doc "Glycemic control: HbA1c, fasting glucose and the glucose trend."
     :members ((:indicator "health.metabolic.hba1c")
               (:indicator "health.biomarker.latest" :params (:marker "glucose"))
               (:indicator "health.biomarker.trend-slope" :params (:marker "glucose"))))
    (inflammation
     :doc "Systemic inflammation: hs-CRP and where it sits in its range."
     :members ((:indicator "health.inflammation.hs-crp")
               (:indicator "health.biomarker.range-position"
                           :params (:marker ("hs_crp" "crp")))))
    (vitamins
     :doc "Vitamin D status and how long since it was drawn."
     :members ((:indicator "health.vitamin-d")
               (:indicator "health.biomarker.days-since-draw"
                           :params (:marker ("vitamin_d" "vitamin_d_25oh")))))
    (overview
     :doc "The whole panel: markers out of range and days since the last draw."
     :members ((:indicator "health.panel.out-of-range-count")
               (:indicator "health.biomarker.days-since-draw"))))
  "Named indicator cohorts.
Each entry is (NAME :doc DOC :members (MEMBER...)).  A MEMBER is
\(:indicator RECIPE-ID [:params PLIST] [:label LABEL]): RECIPE-ID a
catalog indicator id evaluated through
`health-chart-indicator-evaluators', PARAMS its parameters (:marker,
:direction, :bounds, :unit).  Adding a cohort or a member is a pure data
edit; check one with `health-chart-resolve-cohort' or
`health-chart-describe-cohort'."
  :type '(alist :key-type symbol :value-type plist)
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Pure: resolve and list
;; -----------------------------------------------------------------------

(defun health-chart-cohort-names ()
  "Every cohort name, in `health-chart-indicator-cohorts' order."
  (mapcar #'car health-chart-indicator-cohorts))

(defun health-chart--cohort-symbol (name)
  "Cohort NAME (a symbol or string) as a symbol."
  (if (stringp name) (intern name) name))

(defun health-chart--cohort (name)
  "Cohort NAME's plist, or signal `health-chart-unresolvable-cohort'."
  (or (cdr (assq (health-chart--cohort-symbol name) health-chart-indicator-cohorts))
      (signal 'health-chart-unresolvable-cohort
              (list (format "no cohort named %S; use one of %s (see `health-chart-indicator-cohorts')"
                            name (mapconcat #'symbol-name (health-chart-cohort-names) ", "))
                    :code "unknown_cohort" :cohort name))))

(defun health-chart--cohort-member-plan (member)
  "Classify cohort MEMBER as (resolved . PLAN) or (unresolvable . REASON).
PLAN is `health-chart-indicator-plan' plus the member's :label.  Pure."
  (let ((id (and (listp member) (plist-get member :indicator))))
    (if (not (and (stringp id) (not (string-empty-p id))))
        (cons 'unresolvable
              (format "member %S needs :indicator \"RECIPE-ID\"" member))
      (condition-case err
          (cons 'resolved
                (append (apply #'health-chart-indicator-plan id (plist-get member :params))
                        (list :label (plist-get member :label))))
        (health-chart-error (cons 'unresolvable (cadr err)))))))

(defun health-chart-resolve-cohort (name)
  "Resolve cohort NAME to one evaluation plan per member, in order.
A plan is (:id :measure :scope :markers :params :label).  Signal
`health-chart-unresolvable-cohort' when NAME is undefined or any member
cannot be evaluated.  Pure: no catalog, no source."
  (mapcar (lambda (member)
            (let ((res (health-chart--cohort-member-plan member)))
              (if (eq (car res) 'resolved)
                  (cdr res)
                (signal 'health-chart-unresolvable-cohort
                        (list (format "cohort %s: %s" name (cdr res))
                              :code "unresolvable_cohort" :cohort name)))))
          (plist-get (health-chart--cohort name) :members)))

(defun health-chart-list-cohorts ()
  "A summary of every cohort, pure and static.
One (NAME :doc DOC :members N :resolvable R :unresolvable U) per cohort."
  (mapcar
   (lambda (entry)
     (let* ((members (plist-get (cdr entry) :members))
            (resolved (seq-count (lambda (m) (eq (car (health-chart--cohort-member-plan m)) 'resolved))
                                 members)))
       (list (car entry) :doc (plist-get (cdr entry) :doc)
             :members (length members) :resolvable resolved
             :unresolvable (- (length members) resolved))))
   health-chart-indicator-cohorts))

;; -----------------------------------------------------------------------
;; Describe: the catalog probe
;; -----------------------------------------------------------------------

(defun health-chart--cohort-member-ids (name)
  "Distinct :indicator ids of cohort NAME's members, in order."
  (delete-dups (delq nil (mapcar (lambda (m) (and (listp m) (plist-get m :indicator)))
                                 (plist-get (health-chart--cohort name) :members)))))

(defun health-chart--cohort-probe (id)
  "Probe the catalog for ID: (:catalog-live LIVE :catalog-detail D :record R).
LIVE is t (found), :false (absent), :unknown (no catalog configured) or
:error (the catalog failed; D says how)."
  (if (not health-chart-indicator-catalog-function)
      (list :catalog-live :unknown :record nil
            :catalog-detail "no indicator catalog configured; checked against the local evaluators only")
    (condition-case err
        (let ((record (health-chart-indicator-catalog-get id)))
          (if record
              (list :catalog-live t :record record
                    :catalog-detail (format "catalog: %s (revision %s)%s"
                                            (or (plist-get record :name) id)
                                            (or (plist-get record :revision) "?")
                                            (if (member "health" (plist-get record :tags)) ""
                                              ", not tagged health")))
            (list :catalog-live :false :record nil
                  :catalog-detail (format "indicator %s is not in the catalog" id))))
      (health-chart-error
       (list :catalog-live :error :record nil :catalog-detail (cadr err))))))

(defun health-chart--cohort-member-static (member)
  "The pure part of describing cohort MEMBER."
  (let ((res (health-chart--cohort-member-plan member)))
    (list :member member :id (and (listp member) (plist-get member :indicator))
          :status (car res)
          :detail (if (eq (car res) 'resolved)
                      (let ((plan (cdr res)))
                        (format "evaluates as %s%s" (plist-get plan :measure)
                                (if (plist-get plan :markers)
                                    (format " of %s" (string-join (plist-get plan :markers) " or "))
                                  "")))
                    (cdr res)))))

(defun health-chart-describe-cohort (name)
  "Describe cohort NAME: provenance and whether each member resolves.
Returns (:name :doc :provenance :members (MDESC...)); MDESC is (:member
:id :status resolved|unresolvable :detail :catalog-live :catalog-detail
:record).  Calls `health-chart-indicator-catalog-function' once per
member id when one is set (the only I/O here); a catalog failure is
reported per member, never signaled.  Signals
`health-chart-unresolvable-cohort' when NAME is undefined.  See
`health-chart-describe-cohort-explain' for the plan."
  (let ((cohort (health-chart--cohort name)))
    (list :name (health-chart--cohort-symbol name) :doc (plist-get cohort :doc)
          :provenance (format "defcustom `health-chart-indicator-cohorts' (%s)"
                              (or (ignore-errors
                                    (symbol-file 'health-chart-indicator-cohorts 'defvar))
                                  "health-chart-cohort.el"))
          :members (mapcar (lambda (m)
                             (append (health-chart--cohort-member-static m)
                                     (when-let* ((id (and (listp m) (plist-get m :indicator))))
                                       (health-chart--cohort-probe id))))
                           (plist-get cohort :members)))))

(defun health-chart-describe-cohort-explain (name)
  "The plan `health-chart-describe-cohort' follows for NAME.  Pure.
A plist: :name :valid (t or the error message) :members (each the
static resolution, no probe) :calls (each (CATALOG-FUNCTION ID) it would
make; nil without a catalog)."
  (condition-case err
      (let ((fn health-chart-indicator-catalog-function))
        (list :name (health-chart--cohort-symbol name) :valid t
              :members (mapcar #'health-chart--cohort-member-static
                               (plist-get (health-chart--cohort name) :members))
              :calls (when fn (mapcar (lambda (id) (list fn id))
                                      (health-chart--cohort-member-ids name)))))
    (health-chart-error (list :name name :valid (cadr err) :members nil :calls nil))))

;; -----------------------------------------------------------------------
;; Evaluate, fetch, plot
;; -----------------------------------------------------------------------

(defconst health-chart--cohort-fetch-keys '(:person :since :until)
  "Keys of a cohort call that go to `health-chart-source-query'.")

(defun health-chart-cohort-evaluate (name ms &rest props)
  "Indicator values of cohort NAME over canonical measurements MS.
PROPS: :person (default the first in MS), :as-of (default today) and
:records, an alist (RECIPE-ID . CANONICAL-RECORD) whose direction,
bounds and unit fill in what members leave out.  Pure.  Signals
`health-chart-unresolvable-cohort' when a member cannot be evaluated."
  (let ((records (plist-get props :records))
        (ms (health-chart-source-normalize-list ms)))
    (mapcar (lambda (plan)
              (apply #'health-chart-indicator-evaluate (plist-get plan :id) ms
                     (append (when (plist-get plan :label) (list :label (plist-get plan :label)))
                             (list :cohort (symbol-name (health-chart--cohort-symbol name))
                                   :person (plist-get props :person)
                                   :as-of (plist-get props :as-of)
                                   :record (cdr (assoc (plist-get plan :id) records)))
                             (plist-get plan :params))))
            (health-chart-resolve-cohort name))))

(defun health-chart--cohort-fetch-args (args)
  "The `health-chart-source-query' arguments in cohort call ARGS."
  (cl-loop for key in health-chart--cohort-fetch-keys
           when (plist-member args key) append (list key (plist-get args key))))

(defun health-chart-cohort-values (name &rest args)
  "Fetch and evaluate cohort NAME; return its indicator values.
ARGS: :person (default `health-chart-default-person') :since :until
\(passed to `health-chart-source-query') and :as-of (default today).
One source call fetches the person's measurements; when
`health-chart-indicator-catalog-function' is set, one catalog call per
member id fetches its record.  Signals `health-chart-unresolvable-cohort'
before any I/O when the cohort cannot resolve.  See
`health-chart-cohort-values-explain' for the plan."
  (health-chart-resolve-cohort name)
  (let* ((fetch (health-chart--cohort-fetch-args args))
         (ms (apply #'health-chart-source-query fetch))
         (records (when health-chart-indicator-catalog-function
                    (delq nil (mapcar (lambda (id)
                                        (when-let* ((r (health-chart-indicator-catalog-get id)))
                                          (cons id r)))
                                      (health-chart--cohort-member-ids name))))))
    (health-chart-cohort-evaluate
     name ms
     :person (if (plist-member args :person) (plist-get args :person) health-chart-default-person)
     :as-of (plist-get args :as-of) :records records)))

(defun health-chart-cohort-values-explain (name &rest args)
  "The plan `health-chart-cohort-values' follows for NAME and ARGS.  Pure.
A plist: :cohort :valid (t or the error message) :members (evaluation
plans) :fetch (:function :command :args and, for the biomarker CLI,
:argv) :catalog (:function :calls) :as-of."
  (let* ((fetch (health-chart--cohort-fetch-args args))
         (fetch (if (plist-member fetch :person) fetch
                  (append (list :person health-chart-default-person) fetch)))
         (fn health-chart-indicator-catalog-function)
         (plans (condition-case err (health-chart-resolve-cohort name)
                  (health-chart-error (cadr err)))))
    (list :cohort (health-chart--cohort-symbol name)
          :valid (if (stringp plans) plans t)
          :members (unless (stringp plans) plans)
          :fetch (append (list :function health-chart-source-function :command 'query :args fetch)
                         (when (eq health-chart-source-function #'health-chart-source-cli)
                           (list :argv (cons health-chart-source-executable
                                             (apply #'health-chart-source-cli-args 'query fetch)))))
          :catalog (list :function fn
                         :calls (when (and fn (not (stringp plans)))
                                  (mapcar (lambda (id) (list fn id))
                                          (health-chart--cohort-member-ids name))))
          :as-of (or (plist-get args :as-of) (format-time-string "%Y-%m-%d")))))

(defun health-chart--cohort-split (props)
  "Split cohort-plot PROPS into (KIND VALUE-ARGS RENDER-PROPS)."
  (list (or (plist-get props :kind) 'scorecard)
        (append (health-chart--cohort-fetch-args props)
                (when (plist-get props :as-of) (list :as-of (plist-get props :as-of))))
        (apply #'health-chart--plist-drop props :kind health-chart--cohort-fetch-keys)))

(defun health-chart-cohort-plot (name &rest props)
  "Fetch cohort NAME and render it; return the chart string.
PROPS: :kind (scorecard, cohort or staleness; default scorecard), the
fetch args of `health-chart-cohort-values' (:person :since :until
:as-of) and any `health-chart-plot' props.  See
`health-chart-cohort-plot-explain' for the plan."
  (pcase-let ((`(,kind ,value-args ,render) (health-chart--cohort-split props)))
    (health-chart--kind kind)
    (apply #'health-chart-plot kind (apply #'health-chart-cohort-values name value-args) render)))

(defun health-chart-cohort-plot-explain (name &rest props)
  "The plan `health-chart-cohort-plot' follows for NAME and PROPS.  Pure.
`health-chart-cohort-values-explain' plus :plot, the
`health-chart-explain' plan (backend, renderer, args) for the kind."
  (pcase-let ((`(,kind ,value-args ,render) (health-chart--cohort-split props)))
    (append (apply #'health-chart-cohort-values-explain name value-args)
            (list :plot (condition-case err (apply #'health-chart-explain kind nil render)
                          (health-chart-error (list :kind kind :valid (cadr err))))))))

;;;###autoload
(defun health-chart-cohort-view (name &optional kind)
  "Show cohort NAME as a KIND chart (default scorecard) in its own buffer.
Fetches through `health-chart-source-function'.  Interactively, prompts
for the cohort; a prefix argument also prompts for the kind."
  (interactive
   (list (intern (completing-read "Cohort: " (mapcar #'symbol-name (health-chart-cohort-names))
                                  nil t))
         (when current-prefix-arg
           (intern (completing-read "Kind: " '("scorecard" "cohort" "staleness") nil t)))))
  (health-chart-plot-view (or kind 'scorecard) (health-chart-cohort-values name)
                          :buffer (format "*health-chart: %s*" name)))

;; -----------------------------------------------------------------------
;; Health
;; -----------------------------------------------------------------------

(defun health-chart-cohort-doctor-checks ()
  "Doctor rows for indicators: the catalog, the evaluators, each cohort.
Rows are (:name :status pass|fail|skip :detail :remediation).  Calls
neither the catalog nor the source."
  (let ((fn health-chart-indicator-catalog-function)
        (bad (seq-remove (lambda (e) (assq (plist-get (cdr e) :measure) health-chart-indicator-measures))
                         health-chart-indicator-evaluators)))
    (append
     (list
      (cond
       ((null fn)
        (list :name "indicator-catalog" :status 'skip
              :detail "no indicator catalog; cohorts evaluate from the local evaluators"
              :remediation "set `health-chart-indicator-catalog-function' to check members \
against a catalog"))
       ((functionp fn)
        (list :name "indicator-catalog" :status 'pass :detail (format "catalog function %s" fn)))
       (t (list :name "indicator-catalog" :status 'fail
                :detail (format "%S is not a function" fn)
                :remediation "set `health-chart-indicator-catalog-function' to a function or nil")))
      (if bad
          (list :name "indicator-evaluators" :status 'fail
                :detail (format "unknown measure in %s" (mapconcat #'car bad ", "))
                :remediation "use a measure of `health-chart-indicator-measures'")
        (list :name "indicator-evaluators" :status 'pass
              :detail (format "%d recipe ids evaluate locally" (length health-chart-indicator-evaluators)))))
     (mapcar
      (lambda (name)
        (condition-case err
            (list :name (format "cohort:%s" name) :status 'pass
                  :detail (format "%d member(s) resolve" (length (health-chart-resolve-cohort name))))
          (health-chart-error
           (list :name (format "cohort:%s" name) :status 'fail :detail (cadr err)
                 :remediation "fix the member or add a `health-chart-indicator-evaluators' entry"))))
      (health-chart-cohort-names)))))

(provide 'health-chart-cohort)
;;; health-chart-cohort.el ends here
