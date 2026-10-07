;;; health-chart-validate.el --- Strict validation of caller-supplied chart data -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Nothing is drawn until the caller's bindings pass.  Each template
;; declares what it takes in its `x-eas.health' block:
;;
;;   "health": {
;;     "tables": {"data": {"fields": {"time": "time", "value": "number",
;;                                    "note": "?string"},
;;                         "min_rows": 1, "order": "time",
;;                         "rows": [{"le": ["start", "end"],
;;                                   "code": "interval_inverted"}]}},
;;     "rules": [{"le": ["low", "high"], "code": "range_inverted"}]
;;   }
;;
;; A table is a slot holding a list of rows (objects).  Field types:
;; number, nonneg, int, nonnegint, percent (0..100), fraction (0..1),
;; string, time (ISO 8601 date or date-time), date, bool, enum:a|b|c and
;; range:LO:HI; a leading ? makes a field optional.  A row rule {"le":
;; [A, B]} needs A <= B when both are present.  A rule in "rules" does
;; the same for two slots, and "slots": {"as_of": "date"} types a scalar slot.
;; "le" compares numbers or ISO times.  Every failure is a `health-chart-invalid-data'
;; whose data names :code, :path, :index and :field (see
;; `health-chart-error-data').
;;
;; Codes: not_an_object, missing_slot, slot_unknown, slot_type,
;; not_a_list, too_few_rows, not_a_row, missing_field, not_a_number,
;; negative_value, not_an_integer, out_of_range, not_a_string,
;; not_a_time, not_a_date, not_a_bool, not_in_enum, time_not_ascending,
;; plus each rule's own code (range_inverted, interval_inverted, ...).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)
(require 'health-chart-core)

(defun health-chart--finite-p (value)
  "Non-nil when VALUE is a number that is neither NaN nor infinite."
  (and (numberp value)
       (or (integerp value)
           (and (not (isnan value)) (< (abs value) 1.0e+INF)))))

(defun health-chart--name (key)
  "KEY, a keyword or string, as a plain field name."
  (if (keywordp key) (substring (symbol-name key) 1) (format "%s" key)))

(defun health-chart--present-p (row key)
  "Non-nil when plist ROW has a usable KEY (present and not null)."
  (and (plist-member row key) (not (eq (plist-get row key) :null))))

;;; Times

(defconst health-chart--date-regexp "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'")
(defconst health-chart--time-regexp
  (concat "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)"
          "\\(?:[T ]\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)\\(?::\\([0-9]\\{2\\}\\)\\(?:\\.[0-9]+\\)?\\)?"
          "\\(?:Z\\|[+-][0-9]\\{2\\}:?[0-9]\\{2\\}\\)?\\)?\\'"))

(defun health-chart--days-in-month (year month)
  "The number of days in MONTH of YEAR."
  (pcase month
    (2 (if (and (zerop (% year 4)) (or (not (zerop (% year 100))) (zerop (% year 400)))) 29 28))
    ((or 4 6 9 11) 30)
    (_ 31)))

(defun health-chart--time-ok-p (value &optional date-only)
  "Non-nil when VALUE is an ISO 8601 date (or, unless DATE-ONLY, date-time) string."
  (and (stringp value)
       (string-match (if date-only health-chart--date-regexp health-chart--time-regexp) value)
       (let ((year (string-to-number (match-string 1 value)))
             (month (string-to-number (match-string 2 value)))
             (dom (string-to-number (match-string 3 value)))
             (hour (if (match-string 4 value) (string-to-number (match-string 4 value)) 0))
             (minute (if (match-string 5 value) (string-to-number (match-string 5 value)) 0))
             (second (if (match-string 6 value) (string-to-number (match-string 6 value)) 0)))
         (and (<= 1 month 12) (<= 1 dom (health-chart--days-in-month year month))
              (< hour 24) (< minute 60) (< second 61)))))

(defun health-chart--time-key (value)
  "VALUE, an ISO date or date-time, as a string to compare chronologically."
  (let ((s (replace-regexp-in-string " " "T" value)))
    (if (string-match-p "T" s) (substring s 0 (min 19 (length s))) (concat s "T00:00:00"))))

;;; Field types

(defun health-chart--check-type (type value path index field)
  "Signal unless VALUE, found at PATH, is of field TYPE.
TYPE is a field type string without its leading ?.  INDEX and FIELD
locate the row and the field in the error."
  (cl-flet ((bad (code fmt &rest args)
              (apply #'health-chart--invalid code path index field fmt args)))
    (cond
     ((member type '("number" "nonneg" "percent" "fraction"))
      (unless (health-chart--finite-p value)
        (bad "not_a_number" "%s must be a finite number, got %S" path value))
      (pcase type
        ("nonneg" (when (< value 0) (bad "negative_value" "%s must be 0 or more, got %s" path value)))
        ("percent" (unless (<= 0 value 100)
                     (bad "out_of_range" "%s must be between 0 and 100, got %s" path value)))
        ("fraction" (unless (<= 0 value 1)
                      (bad "out_of_range" "%s must be between 0 and 1, got %s" path value)))))
     ((member type '("int" "nonnegint"))
      (unless (integerp value)
        (bad "not_an_integer" "%s must be a whole number, got %S" path value))
      (when (and (equal type "nonnegint") (< value 0))
        (bad "negative_value" "%s must be 0 or more, got %s" path value)))
     ((string-prefix-p "range:" type)
      (let* ((parts (split-string (substring type 6) ":"))
             (lo (string-to-number (car parts))) (hi (string-to-number (cadr parts))))
        (unless (health-chart--finite-p value)
          (bad "not_a_number" "%s must be a finite number, got %S" path value))
        (unless (<= lo value hi)
          (bad "out_of_range" "%s must be between %s and %s, got %s" path lo hi value))))
     ((equal type "string")
      (unless (and (stringp value) (not (string-empty-p value)))
        (bad "not_a_string" "%s must be a non-empty string, got %S" path value)))
     ((equal type "time")
      (unless (health-chart--time-ok-p value)
        (bad "not_a_time" "%s must be an ISO 8601 date or date-time such as 2026-03-01 or 2026-03-01T08:30, got %S"
             path value)))
     ((equal type "date")
      (unless (health-chart--time-ok-p value t)
        (bad "not_a_date" "%s must be an ISO 8601 date such as 2026-03-01, got %S" path value)))
     ((equal type "bool")
      (unless (memq value '(t :false))
        (bad "not_a_bool" "%s must be true or false, got %S" path value)))
     ((string-prefix-p "enum:" type)
      (let ((choices (split-string (substring type 5) "|")))
        (unless (and (stringp value) (member value choices))
          (bad "not_in_enum" "%s must be one of %s, got %S" path (string-join choices ", ") value))))
     (t (error "Unknown health-chart field type %S" type)))))

(defun health-chart--seq (value)
  "VALUE (a list or vector) as a list, else nil."
  (cond ((vectorp value) (append value nil))
        ((proper-list-p value) value)))

(defun health-chart--row-path (table index field)
  "The path of FIELD in row INDEX of TABLE, e.g. data[3].value."
  (concat table (and index (format "[%d]" index)) (and field (concat "." field))))

;;; Tables

(defun health-chart--above-p (a b)
  "Non-nil when A exceeds B: two numbers, or two ISO times (later is greater)."
  (cond ((and (health-chart--finite-p a) (health-chart--finite-p b)) (> a b))
        ((and (health-chart--time-ok-p a) (health-chart--time-ok-p b))
         (string> (health-chart--time-key a) (health-chart--time-key b)))))

(defun health-chart--check-row-rules (rules row table index)
  "Apply the per-row RULES to ROW, row INDEX of TABLE.
Each rule is a plist with :le and :code."
  (dolist (rule rules)
    (when-let* ((pair (plist-get rule :le)))
      (let ((a (aref pair 0)) (b (aref pair 1)))
        (let ((va (plist-get row (eas-key a))) (vb (plist-get row (eas-key b))))
          (when (health-chart--above-p va vb)
            (health-chart--invalid (or (plist-get rule :code) "range_inverted")
                                   (health-chart--row-path table index b) index b
                                   "%s (%s) must not exceed %s (%s)" a va b vb)))))))

(defun health-chart--check-table (table spec value)
  "Validate slot TABLE's VALUE against the table SPEC of the template."
  (let ((rows (health-chart--seq value))
        (fields (plist-get spec :fields))
        (min-rows (or (plist-get spec :min_rows) 1))
        (order (plist-get spec :order))
        previous)
    (unless (or (vectorp value) (proper-list-p value))
      (health-chart--invalid "not_a_list" table nil nil
                             "%s must be a list of rows, got %S" table value))
    (when (< (length rows) min-rows)
      (health-chart--invalid "too_few_rows" table nil nil
                             "%s needs at least %d row%s, got %d" table min-rows
                             (if (= min-rows 1) "" "s") (length rows)))
    (cl-loop
     for row in rows for index from 0
     do (unless (and (consp row) (keywordp (car row)))
          (health-chart--invalid "not_a_row" (health-chart--row-path table index nil) index nil
                                 "%s[%d] must be an object, got %S" table index row))
     (cl-loop
      for (key type) on fields by #'cddr
      for field = (health-chart--name key)
      for optional = (string-prefix-p "?" type)
      for path = (health-chart--row-path table index field)
      do (if (health-chart--present-p row key)
             (health-chart--check-type (string-remove-prefix "?" type) (plist-get row key)
                                       path index field)
           (unless optional
             (health-chart--invalid "missing_field" path index field
                                    "%s is required (%s)" path (string-remove-prefix "?" type)))))
     (health-chart--check-row-rules (append (plist-get spec :rows) nil) row table index)
     (when order
       (let ((now (health-chart--time-key (plist-get row (eas-key order)))))
         (when (and previous (string< now previous))
           (health-chart--invalid "time_not_ascending" (health-chart--row-path table index order)
                                  index order
                                  "%s must not go back in time; %s follows %s (sort oldest first)"
                                  (health-chart--row-path table index order)
                                  (plist-get row (eas-key order)) previous))
         (setq previous now))))
    t))

(defun health-chart--check-rules (rules bindings)
  "Apply the slot RULES (plists with :le and :code) to BINDINGS."
  (dolist (rule rules)
    (when-let* ((pair (plist-get rule :le)))
      (let* ((a (aref pair 0)) (b (aref pair 1))
             (va (plist-get bindings (eas-key a))) (vb (plist-get bindings (eas-key b))))
        (when (health-chart--above-p va vb)
          (health-chart--invalid (or (plist-get rule :code) "range_inverted") b nil b
                                 "%s (%s) must not exceed %s (%s)" a va b vb))))))

;;; Entry points

(defun health-chart--health-meta (template)
  "The `health' block of TEMPLATE's x-eas metadata."
  (plist-get (plist-get template :meta) :health))

(defun health-chart--check-slots (template bindings)
  "Signal when BINDINGS do not fit TEMPLATE's slots (unknown, missing or mistyped)."
  (condition-case err
      (eas-template-bind template bindings)
    (eas-error
     (let* ((plist (eas-error-plist err))
            (code (downcase (or (plist-get plist :code) "slot_type")))
            (slot (plist-get plist :slot)))
       (health-chart--invalid (cond ((equal code "slot_missing") "missing_slot")
                                    ((equal code "invalid_input")
                                     (if slot "slot_unknown" "not_an_object"))
                                    (t code))
                              slot (plist-get plist :index) slot
                              "%s" (plist-get plist :message))))))

(defun health-chart-validate (name bindings)
  "Return t when BINDINGS fit template NAME.
Otherwise signal `health-chart-invalid-data'.
BINDINGS is a plist keyed by slot (what `eas-json-parse' gives for a
JSON object).  The data of the signal names :code, :path, :index and
:field; `health-chart-error-data' reads them.  Nothing is drawn."
  (let* ((template (health-chart--template name))
         (meta (health-chart--health-meta template)))
    (unless (and (listp bindings) (or (null bindings) (keywordp (car bindings))))
      (health-chart--invalid "not_an_object" nil nil nil
                             "Bindings must be an object keyed by slot, got %S" bindings))
    (cl-loop for (table spec) on (plist-get meta :tables) by #'cddr
             for slot = (health-chart--name table)
             do (cond ((and (plist-member bindings table)
                            (not (eq (plist-get bindings table) :null)))
                       (health-chart--check-table slot spec (plist-get bindings table)))
                      ((eq (plist-get spec :optional) t))
                      (t (health-chart--invalid "missing_slot" slot nil slot
                                                "Template %s needs %s" name slot))))
    (cl-loop for (key type) on (plist-get meta :slots) by #'cddr
             for slot = (health-chart--name key)
             when (and (plist-member bindings key) (not (eq (plist-get bindings key) :null)))
             do (health-chart--check-type type (plist-get bindings key) slot nil slot))
    (health-chart--check-rules (append (plist-get meta :rules) nil) bindings)
    (health-chart--check-slots template bindings)
    t))

(defun health-chart-check (name bindings)
  "Like `health-chart-validate', but return t or a plist.
The plist holds :code, :path, :index, :field and :message of the failure.
NAME and BINDINGS are as there."
  (condition-case err
      (health-chart-validate name bindings)
    (health-chart-error (health-chart-error-data err))))

(provide 'health-chart-validate)
;;; health-chart-validate.el ends here
