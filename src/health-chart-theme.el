;;; health-chart-theme.el --- One place for health-chart's colors and margin -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Presentation only.  Every template reads its colors, its warning
;; margin and its surface settings from `health-chart-theme' (the
;; defaults of its slots are filled from it), so red, yellow and green
;; are changed once.  `health-chart-template-theme' overrides single
;; keys for single templates.  A binding always wins over both.
;;
;; The meaning of the colors is fixed (see `health-chart-status'):
;; red is out of range, yellow is near a limit, green is in range, grey
;; is no range to judge against.  Nothing else is drawn in those colors.
;;
;; The theme never holds a clinical value.  Ranges and category bands
;; come from the data.

;;; Code:

(require 'cl-lib)
(require 'eas)

(defgroup health-chart-theme nil
  "Colors and the warning margin of health-chart."
  :group 'health-chart
  :prefix "health-chart-theme-")

(defconst health-chart-theme-slots
  '(:bad "bad_color" :warn "warn_color" :ok "ok_color" :unknown "unknown_color"
    :line "line_color" :warn-margin "warn_margin"
    :sig-figs "sig_figs" :label-max "label_max"
    :ink "ink" :secondary "secondary" :muted "muted" :surface "surface" :grid "grid")
  "Theme key to the template slot it fills.
A template that lacks the slot ignores the key.")

(defconst health-chart-theme-defaults
  '(:bad "#d03b3b" :warn "#e09a00" :ok "#2b9348" :unknown "#898781"
    :line "#2a78d6" :warn-margin 0.2
    :sig-figs 3 :label-max 28
    :ink "#0b0b0b" :secondary "#52514e" :muted "#898781"
    :surface "#fcfcfb" :grid "#e1e0d9")
  "The theme as shipped.  `health-chart-theme' is merged over it.")

(defcustom health-chart-theme nil
  "Colors and warning margin of every health-chart template, as a plist.
Keys (all optional, the default in parentheses):
  :bad      red, a value out of its range (#d03b3b)
  :warn     yellow, a value within the warning margin of a limit (#e09a00)
  :ok       green, a value in range (#2b9348)
  :unknown  grey, a value with no range to judge by (#898781)
  :line     the neutral series color: lines, in-progress and
            \"given\" marks (#2a78d6)
  :warn-margin  the width of the yellow zone inside each limit, as a
            fraction of the range width (0.2).  A one-sided range uses
            the same fraction of its one bound.
  :sig-figs  significant figures of a displayed number, never fewer
            decimals than the reference limits show (3)
  :label-max  the most characters of a row label before an ellipsis (28)
  :ink :secondary :muted :surface :grid  text, background and gridline
            colors.
Set it once; every template follows.  A template's own binding wins."
  :type '(plist :key-type (choice (const :bad) (const :warn) (const :ok) (const :unknown)
                                  (const :line) (const :warn-margin) (const :sig-figs)
                                  (const :label-max) (const :ink)
                                  (const :secondary) (const :muted) (const :surface)
                                  (const :grid))
                :value-type sexp)
  :group 'health-chart-theme)

(defcustom health-chart-template-theme nil
  "Per-template overrides of `health-chart-theme', an alist.
Each element is (TEMPLATE . PLIST) with the keys of `health-chart-theme',
for example (\"vitals-trend\" :warn-margin 0.1)."
  :type '(alist :key-type string :value-type (plist :key-type symbol :value-type sexp))
  :group 'health-chart-theme)

(defun health-chart-theme-get (key &optional template)
  "The value of theme KEY, for TEMPLATE (a name) when given.
Per-template settings come first, then `health-chart-theme', then the
shipped defaults."
  (let ((own (cdr (assoc template health-chart-template-theme))))
    (cond ((plist-member own key) (plist-get own key))
          ((plist-member health-chart-theme key) (plist-get health-chart-theme key))
          (t (plist-get health-chart-theme-defaults key)))))

(defun health-chart-theme-slot-defaults (template)
  "The plist of slot keyword to default value for TEMPLATE, a short name."
  (cl-loop for (key slot) on health-chart-theme-slots by #'cddr
           append (list (eas-key slot) (health-chart-theme-get key template))))

(defun health-chart-theme--patch-slots (slots defaults)
  "SLOTS with the :default of every slot DEFAULTS names replaced, as a copy."
  (cl-loop for (slot def) on slots by #'cddr
           append (list slot
                        (if (plist-member defaults slot)
                            (plist-put (copy-sequence def) :default (plist-get defaults slot))
                          def))))

(defun health-chart-theme--apply (template)
  "TEMPLATE, an eas template record, with the theme as its slot defaults.
Only a slot the template declares is filled.  Records of other
namespaces pass through; the registered record is not changed."
  (let ((name (plist-get template :name)))
    (if (and (stringp name) (string-prefix-p "health/" name))
        (let* ((meta (plist-get template :meta))
               (slots (plist-get meta :slots))
               (defaults (cl-loop for (slot value) on (health-chart-theme-slot-defaults
                                                       (substring name 7))
                                  by #'cddr
                                  when (plist-member slots slot) append (list slot value))))
          (plist-put (copy-sequence template) :meta
                     (plist-put (copy-sequence meta) :slots
                                (health-chart-theme--patch-slots slots defaults))))
      template)))

(advice-add 'eas-template-get :filter-return #'health-chart-theme--apply)

(provide 'health-chart-theme)
;;; health-chart-theme.el ends here
