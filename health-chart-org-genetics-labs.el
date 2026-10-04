;;; health-chart-org-genetics-labs.el --- The health-genetics-labs Org block -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Genotype calls next to the labs they bear on: the explain plan and
;; the writer of the health-genetics-labs dynamic block.

;;; Code:

(require 'health-chart-org-base)
(require 'health-chart-org-blocks)

(defconst health-chart-org--genetics-labs-chart-size '(360 . 180)
  "Pixel (WIDTH . HEIGHT) of a `health-genetics-labs' marker chart.")

(defun health-chart-org--genetics-labs-charts-p (params)
  "Non-nil unless PARAMS turn the per-marker charts off (:charts nil)."
  (let ((v (plist-get params :charts)))
    (not (and (plist-member params :charts) (memq v '(nil no none off))))))

(defun health-chart-org--genetics-labs-chart-params (params marker)
  "The `health-chart' params of PARAMS' small time series of MARKER."
  (append (list :kind 'timeseries)
          (when (plist-member params :person)
            (list :person (health-chart-org--person params)))
          (list :marker marker)
          (cl-loop for key in '(:since :until :backend :format)
                   when (plist-get params key) append (list key (plist-get params key)))
          (list :width (or (plist-get params :width) (car health-chart-org--genetics-labs-chart-size))
                :height (or (plist-get params :height) (cdr health-chart-org--genetics-labs-chart-size))
                :caption (health-chart-marker-label marker))))

(defun health-chart-org--genetics-labs-query (params links)
  "The source `latest' plan for LINKS' markers under PARAMS, or nil if none."
  (let ((spellings (seq-mapcat (lambda (l) (seq-mapcat #'health-chart-genetics-marker-spellings
                                                       (plist-get l :markers)))
                               links)))
    (when spellings
      (let ((params (append (list :markers spellings)
                            (health-chart--plist-drop params :marker :markers))))
        (health-chart-org--source-query 'latest (health-chart-org--fetch-args params)
                                        (health-chart-org--measurement-filter params))))))

(defun health-chart-org-genetics-labs-explain (params &optional org-file)
  "The plan of a `health-genetics-labs' block with PARAMS in ORG-FILE.  Pure.
A plist: :block :params :valid :genetics (the genetics.el calls, from
`health-chart-genetics-calls-explain') :query (the source `latest'
call for every linked marker, nil when none) :genes (each :gene :rsids
:markers :note :rationale :source and :charts, ((MARKER . PLAN)...)
with each marker chart's `health-chart-org-chart-explain' plan)
:disclaimer.  Calls neither genetics.el nor the source."
  (health-chart-org--guard-explain
   "health-genetics-labs" params
   (lambda ()
     (health-chart-org--check params)
     (let* ((genes (health-chart-org--list (plist-get params :genes)))
            (links (health-chart-genetics-links genes))
            (charts (health-chart-org--genetics-labs-charts-p params)))
       (list :genetics (health-chart-genetics-calls-explain
                        (health-chart-org--str (plist-get params :kit))
                        (health-chart-org--str (plist-get params :file))
                        genes)
             :query (health-chart-org--genetics-labs-query params links)
             :genes (mapcar
                     (lambda (l)
                       (let ((markers (mapcar #'health-chart-genetics-marker-id (plist-get l :markers))))
                         (list :gene (plist-get l :gene) :rsids (plist-get l :rsids)
                               :markers markers :note (plist-get l :note)
                               :rationale (plist-get l :rationale) :source (plist-get l :source)
                               :charts (when charts
                                         (mapcar (lambda (m)
                                                   (cons m (health-chart-org-chart-explain
                                                            (health-chart-org--genetics-labs-chart-params
                                                             params m)
                                                            org-file)))
                                                 markers)))))
                     links)
             :disclaimer health-chart-genetics-disclaimer)))))

(defun health-chart-org--value-line (m ms)
  "One list item for measurement M (labelled from MS): status, value, date, range."
  (format "- %s · *%s* %s %s (%s)%s"
          (health-chart-org--status-word (health-chart-status m))
          (health-chart-marker-label-in (plist-get m :marker) ms)
          (health-chart-fmt (plist-get m :value)) (or (plist-get m :unit) "")
          (plist-get m :date)
          (let ((r (health-chart-fmt-range (plist-get m :ref-low) (plist-get m :ref-high))))
            (if (string-empty-p r) "" (format ", reference %s" r)))))

(defun health-chart-org--genetics-labs-calls (plan)
  "Fetch the genotypes of the genetics PLAN as (SUMMARIES . NOTE).
SUMMARIES are per gene; NOTE says why there are none, else nil."
  (let ((g (plist-get plan :genetics)))
    (if (not (plist-get g :available))
        (cons nil (format "/Genotypes not shown: genetics.el is not loaded (%s and %s are undefined); load it, or set =health-chart-genetics-functions=, and refresh this block./"
                          (nth 0 (plist-get g :kit)) (plist-get g :genotype)))
      (condition-case err
          (cons (health-chart-genetics-calls (nth 1 (plist-get g :kit)) (nth 2 (plist-get g :kit))
                                             (mapcar (lambda (x) (plist-get x :gene))
                                                     (plist-get g :genes)))
                nil)
        (error (cons nil (format "/Genotypes not shown: %s/" (health-chart-org--message err))))))))

(defun health-chart-org--genetics-labs-gene (gene summary note ms params)
  "The paragraph of GENE's explain plan with its call SUMMARY.
NOTE is non-nil when no genotypes are available; MS are the latest
measurements; PARAMS the block's."
  (let* ((rsids (string-join (plist-get gene :rsids) ", "))
         (call (cond (note (format "*%s* (%s)." (plist-get gene :gene) rsids))
                     ((not (plist-get summary :called))
                      (format "*%s*: no call at %s in this kit." (plist-get gene :gene) rsids))
                     (t (format "*%s* · %s." (plist-get gene :gene)
                                (health-chart-genetics-call-text summary)))))
         (source (plist-get gene :source))
         (why (format "%s%s%s" (plist-get gene :rationale)
                      (if (plist-get gene :note) (format " %s" (plist-get gene :note)) "")
                      (if source (format " [[%s][%s]]" (cdr source) (car source)) ""))))
    (if (null (plist-get gene :markers))
        (format "%s %s" call why)
      (let ((found (mapcar (lambda (m)
                             (cons m (seq-find (lambda (x) (seq-some (lambda (s) (health-chart-marker-equal
                                                                                  s (plist-get x :marker)))
                                                                     (health-chart-genetics-marker-spellings m)))
                                               ms)))
                           (plist-get (health-chart-genetics-link (plist-get gene :gene)) :markers))))
        (string-join
         (delq nil
               (list
                (format "%s %s" call why)
                (mapconcat (lambda (f)
                             (if (cdr f) (health-chart-org--value-line (cdr f) ms)
                               (format "- *%s*: no results on file."
                                       (health-chart-marker-label
                                        (health-chart-genetics-marker-id (car f))))))
                           found "\n")
                (when (health-chart-org--genetics-labs-charts-p params)
                  (let ((charts
                         (delq nil
                               (mapcar (lambda (f)
                                         (when (cdr f)
                                           (condition-case err
                                               (health-chart-org--chart
                                                (health-chart-org--genetics-labs-chart-params
                                                 params (plist-get (cdr f) :marker)))
                                             (error (health-chart-org--error-line "health-genetics-labs" err)))))
                                       found))))
                    (when charts (string-join charts "\n\n"))))))
         "\n\n")))))

(defun health-chart-org--genetics-labs (params)
  "The text a `health-genetics-labs' block with PARAMS writes."
  (let ((plan (health-chart-org-genetics-labs-explain params)))
    (unless (eq (plist-get plan :valid) t)
      (signal 'health-chart-org-error
              (list (plist-get plan :valid) :code (or (plist-get plan :code) "invalid_block"))))
    (let* ((calls (health-chart-org--genetics-labs-calls plan))
           (note (cdr calls))
           (query (plist-get plan :query))
           (ms (when query
                 (let ((all (health-chart-fill-ranges (health-chart-org--run-query query))))
                   (apply #'append (mapcar (lambda (p) (health-chart-latest (health-chart-filter all :person p)))
                                           (or (health-chart-persons all) '(nil))))))))
      (string-join
       (append (when note (list note))
               (mapcar (lambda (gene)
                         (health-chart-org--genetics-labs-gene
                          gene (seq-find (lambda (s) (equal (plist-get s :gene) (plist-get gene :gene)))
                                         (car calls))
                          note ms params))
                       (plist-get plan :genes))
               (list (format "/%s/" health-chart-genetics-disclaimer)))
       "\n\n"))))

(provide 'health-chart-org-genetics-labs)
;;; health-chart-org-genetics-labs.el ends here
