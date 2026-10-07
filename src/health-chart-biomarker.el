;;; health-chart-biomarker.el --- Bindings from a biomarker/v1 envelope -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; An optional input adapter.  `health-chart-from-biomarker' maps the
;; JSON a biomarker command prints (`biomarker latest|query --format
;; json', the `biomarker/v1' envelope) into the bindings of a lab
;; template.  It is pure: it reads only the envelope it is given, runs no
;; process and touches no file.  Clinical ranges stay with the data
;; source: every ref_low, ref_high, opt_low and opt_high used here is
;; copied from the rows, none is supplied by this package, and a limit
;; the row lacks stays missing (the chart then draws it as unknown, not
;; as in range).
;;
;; An envelope is {"schema": "biomarker/v1", "kind": ..., "data": ROWS}.
;; A row has marker, marker_name, value_canonical, unit_canonical,
;; taken_at, ref_low, ref_high, opt_low, opt_high, flag and category
;; (other fields are ignored).  Rows without a numeric value_canonical
;; (a qualified result such as "<5") are skipped.
;;
;; Templates: lab-results, lab-status-grid, lab-change, lab-trend,
;; lab-panel, lipid-panel, a1c-trend and weight-bmi-trend.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)
(require 'health-chart-core)
(require 'health-chart-validate)
(require 'health-chart-status)

(defconst health-chart-biomarker-templates
  '("lab-results" "lab-status-grid" "lab-change" "lab-trend" "lab-panel"
    "lipid-panel" "a1c-trend" "weight-bmi-trend")
  "The templates `health-chart-from-biomarker' can fill.")

;;; Reading the envelope

(defun health-chart-biomarker--fail (code fmt &rest args)
  "Signal `health-chart-invalid-data' with CODE and message FMT with ARGS."
  (apply #'health-chart--invalid code nil nil nil fmt args))

(defun health-chart-biomarker--rows (envelope)
  "The rows (a list of plists) of ENVELOPE.
ENVELOPE is the parsed envelope (a plist), its JSON text, or the bare
vector of rows.  Signals unless it is a `biomarker/v1' envelope."
  (let ((env (if (stringp envelope) (eas-json-parse envelope) envelope)))
    (cond
     ((vectorp env) (append env nil))
     ((and (listp env) (keywordp (car env)))
      (let ((schema (plist-get env :schema)))
        (when (and schema (not (equal schema "biomarker/v1")))
          (health-chart-biomarker--fail
           "not_biomarker_envelope" "Expected a biomarker/v1 envelope, got schema %S" schema))
        (unless (vectorp (plist-get env :data))
          (health-chart-biomarker--fail
           "not_biomarker_envelope" "A biomarker/v1 envelope needs a data array of rows"))
        (append (plist-get env :data) nil)))
     (t (health-chart-biomarker--fail
         "not_biomarker_envelope"
         "Expected a biomarker/v1 envelope (parsed or as JSON text), got %S" envelope)))))

(defun health-chart-biomarker--num (row key)
  "ROW's KEY as a number, or nil when missing, null or not a number."
  (let ((v (plist-get row key)))
    (and (numberp v) v)))

(defun health-chart-biomarker--str (row key)
  "ROW's KEY as a non-empty string, or nil."
  (let ((v (plist-get row key)))
    (and (stringp v) (not (string-empty-p v)) v)))

(defun health-chart-biomarker--usable (rows)
  "ROWS that name a marker, a draw date and carry a numeric canonical value."
  (seq-filter (lambda (row)
                (and (health-chart-biomarker--str row :marker)
                     (health-chart-biomarker--str row :taken_at)
                     (health-chart-biomarker--num row :value_canonical)))
              rows))

(defun health-chart-biomarker--sorted (rows)
  "ROWS oldest draw first (stable)."
  (sort (copy-sequence rows)
        (lambda (a b)
          (string< (health-chart--time-key (plist-get a :taken_at))
                   (health-chart--time-key (plist-get b :taken_at))))))

(defun health-chart-biomarker--markers (rows)
  "The markers of ROWS in order of first appearance."
  (seq-uniq (mapcar (lambda (row) (plist-get row :marker)) rows)))

(defun health-chart-biomarker--of (rows marker)
  "The ROWS of MARKER, oldest first."
  (health-chart-biomarker--sorted
   (seq-filter (lambda (row) (equal (plist-get row :marker) marker)) rows)))

(defun health-chart-biomarker--select (rows opts)
  "The usable ROWS, narrowed by the :markers and :category in OPTS."
  (let* ((rows (health-chart-biomarker--usable rows))
         (markers (plist-get opts :markers))
         (category (plist-get opts :category)))
    (when markers
      (setq rows (seq-filter (lambda (row) (member (plist-get row :marker) markers)) rows)))
    (when category
      (setq rows (seq-filter (lambda (row) (equal (plist-get row :category) category)) rows)))
    (or rows
        (health-chart-biomarker--fail
         "no_rows" "The envelope has no usable rows%s (a row needs marker, taken_at and a numeric value_canonical)"
         (if (or markers category) " for the markers or category asked for" "")))))

(defun health-chart-biomarker--one-marker (rows opts template)
  "The rows of the single marker TEMPLATE draws, from ROWS and OPTS' :marker.
Signals when the envelope holds several markers and none is named."
  (let* ((rows (health-chart-biomarker--select rows opts))
         (marker (or (plist-get opts :marker)
                     (let ((all (health-chart-biomarker--markers rows)))
                       (if (= (length all) 1) (car all)
                         (health-chart-biomarker--fail
                          "marker_required"
                          "%s draws one marker; name it with :marker (the envelope has %s)"
                          template (string-join all ", ")))))))
    (or (health-chart-biomarker--of rows marker)
        (health-chart-biomarker--fail
         "marker_not_found" "The envelope has no usable rows of marker %S" marker))))

;;; Pieces shared by the mappings

(defun health-chart-biomarker--limits (row &rest keys)
  "The plist of those KEYS that ROW has as numbers (the limits it has)."
  (cl-loop for k in keys
           for v = (health-chart-biomarker--num row k)
           when v append (list k v)))

(defun health-chart-biomarker--ref (row &optional low-key high-key)
  "ROW's range as a plist of LOW-KEY and HIGH-KEY (default :ref_low :ref_high).
A limit ROW lacks is left out."
  (let ((lk (or low-key :ref_low)) (hk (or high-key :ref_high)))
    (health-chart-biomarker--limits row lk hk)))

(defun health-chart-biomarker--ref-opt (row)
  "ROW's reference range and, inside it, its optimal range, as one plist.
An optimal limit that lies outside the reference range on its side, or
an inverted optimal range, is left out: red is only ever the reference."
  (let* ((ref (health-chart-biomarker--ref row))
         (opt (health-chart-status--opt (plist-get ref :ref_low) (plist-get ref :ref_high)
                                        (health-chart-biomarker--num row :opt_low)
                                        (health-chart-biomarker--num row :opt_high)))
         (ol (car opt)) (oh (cdr opt)))
    (when (and ol oh (> ol oh)) (setq ol nil oh nil))
    (append ref (health-chart-biomarker--with :opt_low ol :opt_high oh))))

(defun health-chart-biomarker--name (row)
  "ROW's display name: marker_name, else the marker."
  (or (health-chart-biomarker--str row :marker_name) (plist-get row :marker)))

(defun health-chart-biomarker--unit (row)
  "ROW's canonical unit, or nil."
  (health-chart-biomarker--str row :unit_canonical))

(defun health-chart-biomarker--with (&rest plist)
  "PLIST without the pairs whose value is nil."
  (cl-loop for (k v) on plist by #'cddr when v append (list k v)))

(defun health-chart-biomarker--title (opts default)
  "OPTS' :title, else DEFAULT."
  (or (plist-get opts :title) default))

(defun health-chart-biomarker--round (x)
  "X rounded to six decimals, which hides float noise from arithmetic."
  (/ (fround (* x 1.0e6)) 1.0e6))

(defun health-chart-biomarker--latest (rows marker)
  "The newest of ROWS for MARKER."
  (car (last (health-chart-biomarker--of rows marker))))

;;; The mappings, one per template

(defun health-chart-biomarker--lab-results (rows opts)
  "Bindings of lab-results from ROWS and OPTS: the newest result per marker."
  (let ((rows (health-chart-biomarker--select rows opts)))
    (list :title (health-chart-biomarker--title opts "Latest results")
          :data (vconcat
                 (mapcar
                  (lambda (marker)
                    (let ((row (health-chart-biomarker--latest rows marker)))
                      (append (list :analyte (health-chart-biomarker--name row)
                                    :value (plist-get row :value_canonical))
                              (health-chart-biomarker--with :unit (health-chart-biomarker--unit row))
                              (health-chart-biomarker--ref-opt row))))
                  (health-chart-biomarker--markers rows))))))

(defun health-chart-biomarker--ranged (rows opts)
  "ROWS of the markers that have a reference range in some row.
All ROWS when OPTS name :markers or set :all-markers, or when no marker
has a range (the grid then draws them grey, no range)."
  (let ((ranged (seq-uniq
                 (mapcar (lambda (row) (plist-get row :marker))
                         (seq-filter (lambda (row) (or (health-chart-biomarker--num row :ref_low)
                                                       (health-chart-biomarker--num row :ref_high)))
                                     rows)))))
    (if (or (plist-get opts :markers) (plist-get opts :all-markers) (null ranged))
        rows
      (seq-filter (lambda (row) (member (plist-get row :marker) ranged)) rows))))

(defun health-chart-biomarker--lab-status-grid (rows opts)
  "Bindings of lab-status-grid from ROWS and OPTS: every result, oldest first.
Only markers with a reference range, unless OPTS say otherwise
\(`health-chart-biomarker--ranged')."
  (let ((rows (health-chart-biomarker--sorted
               (health-chart-biomarker--ranged (health-chart-biomarker--select rows opts) opts))))
    (list :title (health-chart-biomarker--title opts "Results by draw")
          :data (vconcat
                 (mapcar (lambda (row)
                           (append (list :time (plist-get row :taken_at)
                                         :analyte (health-chart-biomarker--name row)
                                         :value (plist-get row :value_canonical))
                                   (health-chart-biomarker--ref-opt row)))
                         rows)))))

(defun health-chart-biomarker--lab-change (rows opts)
  "Bindings of lab-change from ROWS and OPTS: each marker's two newest results.
The later result's range is used.  A marker with one result is skipped."
  (let* ((rows (health-chart-biomarker--select rows opts))
         (pairs (cl-loop for marker in (health-chart-biomarker--markers rows)
                         for own = (health-chart-biomarker--of rows marker)
                         when (cdr own) collect (last own 2))))
    (unless pairs
      (health-chart-biomarker--fail
       "too_few_results" "lab-change needs a marker with at least two results"))
    (list :title (health-chart-biomarker--title opts "Change between two draws")
          :data (vconcat
                 (mapcar (lambda (pair)
                           (let ((before (car pair)) (after (cadr pair)))
                             (append (list :analyte (health-chart-biomarker--name after)
                                           :before (plist-get before :value_canonical)
                                           :after (plist-get after :value_canonical))
                                     (health-chart-biomarker--with
                                      :unit (health-chart-biomarker--unit after))
                                     (health-chart-biomarker--ref-opt after))))
                         pairs)))))

(defun health-chart-biomarker--axis-title (row)
  "\"Name (unit)\" for ROW."
  (let ((unit (health-chart-biomarker--unit row)))
    (if unit (format "%s (%s)" (health-chart-biomarker--name row) unit)
      (health-chart-biomarker--name row))))

(defun health-chart-biomarker--lab-trend (rows opts)
  "Bindings of lab-trend from ROWS and OPTS: one marker over time.
The range and the optimal band are the newest result's."
  (let* ((own (health-chart-biomarker--one-marker rows opts "lab-trend"))
         (last-row (car (last own)))
         (ref (health-chart-biomarker--ref-opt last-row)))
    (append
     (list :title (health-chart-biomarker--title opts (health-chart-biomarker--name last-row))
           :y_title (health-chart-biomarker--axis-title last-row)
           :data (vconcat (mapcar (lambda (row)
                                    (list :time (plist-get row :taken_at)
                                          :value (plist-get row :value_canonical)))
                                  own)))
     (health-chart-biomarker--with :low (health-chart-biomarker--num last-row :ref_low)
                                   :high (health-chart-biomarker--num last-row :ref_high))
     (health-chart-biomarker--with :opt_low (plist-get ref :opt_low)
                                   :opt_high (plist-get ref :opt_high))
     (and (plist-get ref :opt_low) (plist-get ref :opt_high) (list :show_optimal t)))))

(defun health-chart-biomarker--lab-panel (rows opts)
  "Bindings of lab-panel from ROWS and OPTS: a panel per marker, newest range."
  (let* ((rows (health-chart-biomarker--select rows opts))
         (markers (health-chart-biomarker--markers rows)))
    (list :title (health-chart-biomarker--title opts "Lab panel")
          :panels (vconcat
                   (mapcar
                    (lambda (marker)
                      (let ((row (health-chart-biomarker--latest rows marker)))
                        (append
                         (list :analyte marker :label (health-chart-biomarker--name row))
                         (health-chart-biomarker--with
                          :unit (and (health-chart-biomarker--unit row)
                                     (format " (%s)" (health-chart-biomarker--unit row))))
                         (health-chart-biomarker--with
                          :low (health-chart-biomarker--num row :ref_low)
                          :high (health-chart-biomarker--num row :ref_high)))))
                    markers))
          :data (vconcat (mapcar (lambda (row)
                                   (list :time (plist-get row :taken_at)
                                         :analyte (plist-get row :marker)
                                         :value (plist-get row :value_canonical)))
                                 (health-chart-biomarker--sorted rows))))))

(defun health-chart-biomarker--goal (row directions)
  "ROW's goal as (GOAL DIRECTION . REF-LIMIT), or nil when it has no limit to use.
DIRECTIONS is an alist of marker to \"below\" or \"above\".  The goal is the
optimal limit, else the reference limit.  With only an upper limit the
goal is to stay below it, with only a lower limit above it; with both,
the entry of DIRECTIONS decides (default below).  REF-LIMIT is the
reference limit on the goal's side when it differs from the goal (the
bar is red only beyond it), else nil."
  (let* ((ref (health-chart-biomarker--ref-opt row))
         (high (or (plist-get ref :opt_high) (plist-get ref :ref_high)))
         (low (or (plist-get ref :opt_low) (plist-get ref :ref_low)))
         (wanted (cdr (assoc (plist-get row :marker) directions)))
         (below (cond ((and high low) (not (equal wanted "above"))) (high t)))
         (goal (if below high low))
         (limit (plist-get ref (if below :ref_high :ref_low))))
    (when goal
      (cons goal (cons (if below "below" "above")
                       (and limit (/= limit goal) limit))))))

(defun health-chart-biomarker--lipid-panel (rows opts)
  "Bindings of lipid-panel from ROWS: each marker's newest result and goal.
The goal comes from the row's optimal (else reference) limit and the
reference limit on its side is the row's ref_limit: a result is red only
beyond that, yellow between it and the goal.  OPTS'
:directions maps a marker with both limits to \"below\" or \"above\".
The previous result, when there is one, is the hollow prior marker."
  (let* ((rows (health-chart-biomarker--select rows opts))
         (data
          (cl-loop
           for marker in (health-chart-biomarker--markers rows)
           for own = (health-chart-biomarker--of rows marker)
           for row = (car (last own))
           for goal = (health-chart-biomarker--goal row (plist-get opts :directions))
           when goal
           collect (append
                    (list :analyte (health-chart-biomarker--name row)
                          :value (plist-get row :value_canonical)
                          :goal (car goal) :direction (cadr goal))
                    (health-chart-biomarker--with
                     :ref_limit (cddr goal)
                     :unit (health-chart-biomarker--unit row)
                     :prior (and (cdr own)
                                 (plist-get (car (last own 2)) :value_canonical)))))))
    (unless data
      (health-chart-biomarker--fail
       "no_goals" "lipid-panel needs a marker with an optimal or reference limit to use as its goal"))
    (list :title (health-chart-biomarker--title opts "Lipid panel")
          :data (vconcat data))))

(defun health-chart-biomarker--bands (row opts)
  "Category bands for ROW's reference range, or OPTS' :bands.
The bands cut the range at the edges of its warning zones."
  (or (plist-get opts :bands)
      (let ((low (health-chart-biomarker--num row :ref_low))
            (high (health-chart-biomarker--num row :ref_high)))
        (and (or low high)
             (vconcat
              (mapcar (lambda (band)
                        (cl-loop for (k v) on band by #'cddr
                                 append (list k (if (numberp v) (health-chart-biomarker--round v) v))))
                      (health-chart-status-bands low high (plist-get opts :margin))))))))

(defun health-chart-biomarker--a1c-trend (rows opts)
  "Bindings of a1c-trend from ROWS: the marker of OPTS (default \"hba1c\").
The bands are cut from the newest reference range, the target line is
its optimal upper limit when it has one."
  (let* ((own (health-chart-biomarker--one-marker
               rows (append (list :marker (or (plist-get opts :marker) "hba1c")) opts) "a1c-trend"))
         (last-row (car (last own)))
         (bands (health-chart-biomarker--bands last-row opts)))
    (unless bands
      (health-chart-biomarker--fail
       "no_range" "a1c-trend draws category bands; the newest result has no ref_low or ref_high (pass :bands)"))
    (append
     (list :title (health-chart-biomarker--title opts (health-chart-biomarker--name last-row))
           :y_title (health-chart-biomarker--axis-title last-row)
           :bands bands
           :data (vconcat (mapcar (lambda (row)
                                    (list :time (plist-get row :taken_at)
                                          :value (plist-get row :value_canonical)))
                                  own)))
     (health-chart-biomarker--with :target (health-chart-biomarker--num last-row :opt_high)))))

(defun health-chart-biomarker--height-m (rows opts)
  "The height in metres of ROWS and OPTS: :height-m, else a \"height\" marker."
  (or (plist-get opts :height-m)
      (when-let* ((row (health-chart-biomarker--latest rows "height"))
                  (v (plist-get row :value_canonical)))
        (pcase (health-chart-biomarker--unit row)
          ("cm" (/ v 100.0))
          ("m" v)))
      (health-chart-biomarker--fail
       "height_required"
       "weight-bmi-trend needs the height: pass :height-m or include a \"height\" marker in m or cm")))

(defun health-chart-biomarker--weight-bmi-trend (rows opts)
  "Bindings of weight-bmi-trend from ROWS: the \"weight\" marker in kg.
Height comes from OPTS' :height-m or a \"height\" marker.  The bands
come from OPTS' :bands or are cut from the reference range of a \"bmi\"
marker when the envelope has one."
  (let* ((usable (health-chart-biomarker--usable rows))
         (own (health-chart-biomarker--of usable (or (plist-get opts :marker) "weight")))
         (bmi (health-chart-biomarker--latest usable "bmi"))
         (bands (health-chart-biomarker--bands bmi opts)))
    (unless own
      (health-chart-biomarker--fail "marker_not_found" "The envelope has no usable rows of marker \"weight\""))
    (unless (member (health-chart-biomarker--unit (car own)) '("kg" nil))
      (health-chart-biomarker--fail
       "unit_not_kg" "weight-bmi-trend takes kilograms, the envelope has %s"
       (health-chart-biomarker--unit (car own))))
    (unless bands
      (health-chart-biomarker--fail
       "no_range" "weight-bmi-trend draws category bands: pass :bands or include a \"bmi\" marker with a reference range"))
    (list :title (health-chart-biomarker--title opts "BMI")
          :height_m (health-chart-biomarker--height-m usable opts)
          :bands bands
          :data (vconcat (mapcar (lambda (row)
                                   (list :time (plist-get row :taken_at)
                                         :weight_kg (plist-get row :value_canonical)))
                                 own)))))

;;; Entry point

(defun health-chart-biomarker--display (name opts bindings)
  "BINDINGS of template NAME with the display slots OPTS asks for laid over.
:decimals, :sig-figs, :label-max, :max-draws and :include-frequent become
the slots decimals, sig_figs, label_max, max_draws and include_frequent
when the template declares them.
Display only: no number in BINDINGS changes."
  (let ((slots (plist-get (plist-get (health-chart--template name) :meta) :slots)))
    (cl-loop for (opt slot) in '((:decimals :decimals) (:sig-figs :sig_figs) (:label-max :label_max)
                                  (:max-draws :max_draws))
             when (and (numberp (plist-get opts opt)) (plist-member slots slot))
             do (setq bindings (plist-put (copy-sequence bindings) slot (plist-get opts opt))))
    (when (and (plist-get opts :include-frequent) (plist-member slots :include_frequent))
      (setq bindings (plist-put (copy-sequence bindings) :include_frequent t)))
    bindings))

;;;###autoload
(defun health-chart-from-biomarker (template envelope &rest opts)
  "Bindings for TEMPLATE from ENVELOPE, a `biomarker/v1' envelope.
ENVELOPE is what `biomarker latest|query --format json' prints: the
parsed plist (see `health-chart-read-bindings'), the JSON text, or just
its data rows.  The result renders with `health-chart-render'.  No
process is run and no file is read.

TEMPLATE is one of `health-chart-biomarker-templates'.  OPTS:
  :title      the chart title
  :markers    list of markers to draw (the multi-marker templates)
  :category   keep only rows of this category
  :marker     the marker a one-marker template draws (lab-trend: required
              when the envelope holds several; a1c-trend: default hba1c)
  :height-m   weight-bmi-trend: height in metres (else a height marker)
  :bands      a1c-trend, weight-bmi-trend: category bands
              [{label, low, high, status}] instead of the ones cut from
              the reference range
  :margin     a1c-trend, weight-bmi-trend: warning margin of the cut bands
  :directions lipid-panel: alist of marker to \"below\" or \"above\" for a
              marker that has both limits
  :all-markers lab-status-grid: every marker; by default only markers with
              a reference range in some row are drawn (all of them when
              none has one, or when :markers names them)
  :include-frequent lab-status-grid: keep markers drawn far more often
              than the rest (the slot include_frequent)
  :max-draws  lab-status-grid: show only the latest N draw dates (0: all);
              the slot max_draws.  Without it a text view shows as many
              draws as its width holds.
  :decimals :sig-figs :label-max   display precision and label width, the
              slots decimals, sig_figs and label_max of the template.  They
              change the text drawn, never the numbers: a value of 82.9167
              still sits in the data as it came and is judged as it came.
Ranges come from the rows only; a missing limit stays missing."
  (let ((name (if (symbolp template) (symbol-name template) template))
        (rows (health-chart-biomarker--rows envelope)))
    (health-chart-biomarker--display
     name opts
     (pcase name
       ("lab-results" (health-chart-biomarker--lab-results rows opts))
       ("lab-status-grid" (health-chart-biomarker--lab-status-grid rows opts))
       ("lab-change" (health-chart-biomarker--lab-change rows opts))
       ("lab-trend" (health-chart-biomarker--lab-trend rows opts))
       ("lab-panel" (health-chart-biomarker--lab-panel rows opts))
       ("lipid-panel" (health-chart-biomarker--lipid-panel rows opts))
       ("a1c-trend" (health-chart-biomarker--a1c-trend rows opts))
       ("weight-bmi-trend" (health-chart-biomarker--weight-bmi-trend rows opts))
       (_ (health-chart-biomarker--fail
           "unsupported_template" "No biomarker mapping for template %S; supported: %s"
           name (string-join health-chart-biomarker-templates ", ")))))))

(provide 'health-chart-biomarker)
;;; health-chart-biomarker.el ends here
