;;; eas-examples.el --- write the eas templates' example bindings -*- lexical-binding: t; -*-

;; Each eas template declares an example (`x-eas.example'): bindings that
;; render as they are, for `eas describe', `bin/eas example' and the
;; tests.  This writes them to examples/eas/NAME.data.json from the
;; package's synthetic data, keeping only the slots a template needs
;; beyond its defaults (data, words, and each kind's own).
;;
;; Regenerate (eas.el beside this checkout, or EAS=PATH):
;;
;;   emacs -Q --batch -L . -L ../eas.el/src -l examples/eas-examples.el
;;
;; and review the diff.  Synthetic data only.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'eas)
(require 'health-chart)
(require 'health-chart-eas-route)

(defconst eas-examples--dir
  (expand-file-name "eas" (file-name-directory (or load-file-name buffer-file-name))))

(defconst eas-examples--specs
  '((timeseries :person "alex" :marker "ldl_c")
    (compare :marker "vitamin_d")
    (panel :person "alex" :marker ("ldl_c" "hdl_c" "vitamin_d" "tsh"))
    (trend :person "alex" :marker "ldl_c")
    (lollipop :person "alex" :marker "crp")
    (bullet :person "alex" :marker ("ldl_c" "hdl_c" "glucose" "vitamin_d" "tsh"))
    (heatmap :person "alex" :marker ("ldl_c" "hdl_c" "glucose" "vitamin_d"))
    (delta :person "alex" :marker ("ldl_c" "hdl_c" "glucose" "vitamin_d" "tsh"))
    (staleness)
    (strip :person "alex" :marker ("ldl_c" "hdl_c" "glucose" "vitamin_d"))
    (dumbbell :person "alex" :marker ("ldl_c" "hdl_c" "glucose" "vitamin_d"))
    (dual :person "alex" :marker ("glucose" "hba1c"))
    (inrange :person "alex" :marker ("ldl_c" "hdl_c" "glucose" "vitamin_d")))
  "Each templated kind with the props its example is built from.")

(defconst eas-examples--keep
  '(:data :title :subtitle :y_title :as_of :due_days :stale_days
    :column_1 :column_2 :column_3 :column_4 :has_column_2 :has_column_3 :has_column_4
    :series_domain :series_range :series_shape
    :verdict_domain :verdict_range :state_domain :state_range
    :left_color :right_color :left_title :right_title :left_domain :right_domain
    :x_format :x_ticks :row_step :status_domain :status_range :status_shape)
  "The binding slots an example keeps; the rest are template defaults.")

(defun eas-examples--clean (value)
  "VALUE as JSON-encodable: no nil members, symbols as names."
  (cond
   ((vectorp value) (vconcat (mapcar #'eas-examples--clean value)))
   ((and (consp value) (keywordp (car value)))
    (cl-loop for (k v) on value by #'cddr
             when (and v (not (eq v :null)))
             append (list k (eas-examples--clean v))))
   ((consp value) (vconcat (mapcar #'eas-examples--clean value)))
   ((and (symbolp value) value (not (memq value '(t :false :null))))
    (symbol-name value))
   (t value)))

(defun eas-examples--data (kind)
  "Synthetic data for KIND's example."
  (if (eq kind 'staleness)
      (mapcar (lambda (v) (list :id (plist-get v :id) :label (plist-get v :label)
                                :value (plist-get v :value) :unit (plist-get v :unit)
                                :date (plist-get v :date) :as-of (plist-get v :as-of)
                                :marker (plist-get v :marker) :person (plist-get v :person)
                                :cohort (plist-get v :cohort)))
              (seq-take (health-chart--example-indicator-values) 5))
    (health-chart--example-measurements)))

(defun eas-examples-write ()
  "Write every example to `eas-examples--dir'."
  (make-directory eas-examples--dir t)
  (dolist (spec eas-examples--specs)
    (let* ((kind (car spec))
           (bindings (health-chart-eas-bindings kind (eas-examples--data kind) (cdr spec)))
           (kept (cl-loop for (k v) on bindings by #'cddr
                          when (memq k eas-examples--keep) append (list k v)))
           (name (health-chart-eas-template kind))
           (file (expand-file-name (concat name ".data.json") eas-examples--dir)))
      (let ((coding-system-for-write 'utf-8))
        (with-temp-file file
          (insert (eas-json-pretty (eas-examples--clean kept)) "\n")))
      (message "wrote %s" file))))

(when noninteractive (eas-examples-write))

;;; eas-examples.el ends here
