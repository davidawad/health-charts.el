;;; health-chart-dashboard.el --- The `health-charts' dashboard buffer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; M-x health-charts (an alias of `health-chart-dashboard') opens a dashboard of one person's biomarkers: a
;; sparkline table to navigate, then the sections in
;; `health-chart-dashboard-sections' (range bars and the out-of-range
;; heatmap by default).  Data comes from `health-chart-source-query', so
;; it follows whatever `health-chart-source-function' is configured.
;;
;;   RET  open the marker at point as a time series
;;   m    compare the marker at point across every person
;;   s    select person          c    filter by category
;;   C    select indicator cohort K    cohort panel
;;   v    small-multiples panel  d    change between the last two draws
;;   g    refetch and redraw     t    toggle text / SVG
;;   r    toggle reference band  o    toggle optimal band
;;   n/p  next / previous marker q    quit

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'text-property-search)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-plot)
(require 'health-chart-cohort)

(defcustom health-chart-dashboard-buffer-name "*health-charts*"
  "Name of the dashboard buffer."
  :type 'string
  :group 'health-charts)

(defcustom health-chart-dashboard-sections '(bullet heatmap)
  "Chart kinds drawn below the sparkline table, in order."
  :type '(repeat (choice (const bullet) (const heatmap) (const delta) (const panel)))
  :group 'health-charts)

(defcustom health-chart-dashboard-cohort nil
  "Indicator cohort the dashboard starts with, or nil for none.
A name of `health-chart-indicator-cohorts'; change it in the dashboard
with \<health-chart-dashboard-mode-map>\[health-chart-dashboard-select-cohort]."
  :type '(choice (const :tag "None" nil) symbol)
  :group 'health-charts)

(defcustom health-chart-dashboard-cohort-sections '(scorecard)
  "Indicator chart kinds drawn for the selected cohort, in order."
  :type '(repeat (choice (const scorecard) (const cohort) (const staleness)))
  :group 'health-charts)

(defcustom health-chart-dashboard-backend 'auto
  "Backend the dashboard starts with for its sections.
`auto' follows `health-chart-backend' selection (Vega-Lite or gnuplot
images in a GUI, gnuplot or native text in a terminal); or name one of
`health-chart-backends'.  The sparkline table is always text, so RET
works on its rows."
  :type '(choice (const auto) (const vega-lite) (const gnuplot) (const text)
                 (const :tag "svg (native, obsolete)" svg))
  :group 'health-charts)

(defvar-local health-chart-dashboard--person nil "Person shown.")
(defvar-local health-chart-dashboard--category nil "Category filter, nil for all.")
(defvar-local health-chart-dashboard--cohort nil "Indicator cohort shown, or nil.")
(defvar-local health-chart-dashboard--backend nil "Backend for the sections.")
(defvar-local health-chart-dashboard--ref nil "Whether the reference band shows.")
(defvar-local health-chart-dashboard--optimal nil "Whether the optimal band shows.")
(defvar-local health-chart-dashboard--data nil "Fetched measurements of the person.")
(defvar-local health-chart-dashboard--persons nil "Every known person.")
(defvar-local health-chart-dashboard--error nil "The last source error, or nil.")

(defvar health-chart-dashboard-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "RET") #'health-chart-dashboard-open)
    (define-key m (kbd "m") #'health-chart-dashboard-compare)
    (define-key m (kbd "s") #'health-chart-dashboard-select-person)
    (define-key m (kbd "c") #'health-chart-dashboard-select-category)
    (define-key m (kbd "C") #'health-chart-dashboard-select-cohort)
    (define-key m (kbd "K") #'health-chart-dashboard-cohort-panel)
    (define-key m (kbd "v") #'health-chart-dashboard-panel)
    (define-key m (kbd "d") #'health-chart-dashboard-delta)
    (define-key m (kbd "g") #'health-chart-dashboard-refresh)
    (define-key m (kbd "t") #'health-chart-dashboard-toggle-backend)
    (define-key m (kbd "r") #'health-chart-dashboard-toggle-ref)
    (define-key m (kbd "o") #'health-chart-dashboard-toggle-optimal)
    (define-key m (kbd "n") #'health-chart-dashboard-next)
    (define-key m (kbd "p") #'health-chart-dashboard-previous)
    m)
  "Keymap for `health-chart-dashboard-mode'.")

(define-derived-mode health-chart-dashboard-mode special-mode "Health-Charts"
  "Major mode for the `health-charts' biomarker dashboard.
\\{health-chart-dashboard-mode-map}"
  (setq truncate-lines t))

;; -----------------------------------------------------------------------
;; Data
;; -----------------------------------------------------------------------

(defun health-chart-dashboard--fetch ()
  "Fetch the person list and the person's measurements; record errors."
  (setq health-chart-dashboard--error nil)
  (condition-case err
      (progn
        (setq health-chart-dashboard--persons
              (health-chart-persons (health-chart-source-latest :person nil)))
        (unless health-chart-dashboard--person
          (setq health-chart-dashboard--person
                (or health-chart-default-person (car health-chart-dashboard--persons))))
        (setq health-chart-dashboard--data
              (health-chart-source-query :person health-chart-dashboard--person)))
    (health-chart-error
     (setq health-chart-dashboard--data nil
           health-chart-dashboard--error (cadr err)))))

(defun health-chart-dashboard--visible ()
  "The fetched measurements passing the category filter."
  (health-chart-filter health-chart-dashboard--data
                       :category health-chart-dashboard--category))

(defun health-chart-dashboard--props ()
  "Return chart props reflecting the dashboard's band and backend state."
  (list :person health-chart-dashboard--person
        :ref health-chart-dashboard--ref :optimal health-chart-dashboard--optimal
        :backend health-chart-dashboard--backend))

;; -----------------------------------------------------------------------
;; Drawing
;; -----------------------------------------------------------------------

(defun health-chart-dashboard--header ()
  "The dashboard's status and key-hint lines."
  (concat
   (propertize "Health charts" 'face 'health-chart-header)
   (propertize
    (format " · %s · category: %s · cohort: %s · %s · bands: %s\n"
            (or health-chart-dashboard--person "everyone")
            (or health-chart-dashboard--category "all")
            (or health-chart-dashboard--cohort "none")
            (health-chart--usable-backend health-chart-dashboard--backend
                                          (car health-chart-dashboard-sections))
            (string-join (delq nil (list (and health-chart-dashboard--ref "reference")
                                         (and health-chart-dashboard--optimal "optimal")))
                         "+"))
    'face 'health-chart-dim)
   (propertize
    (substitute-command-keys
     "\\<health-chart-dashboard-mode-map>\\[health-chart-dashboard-open] open  \
\\[health-chart-dashboard-compare] compare  \\[health-chart-dashboard-select-person] person  \
\\[health-chart-dashboard-select-category] category  \\[health-chart-dashboard-select-cohort] cohort  \
\\[health-chart-dashboard-cohort-panel] cohort panel  \\[health-chart-dashboard-panel] panel  \
\\[health-chart-dashboard-delta] change  \\[health-chart-dashboard-refresh] refresh  \
\\[health-chart-dashboard-toggle-backend] text/image  \\[health-chart-dashboard-toggle-ref] ref  \
\\[health-chart-dashboard-toggle-optimal] optimal  \\[quit-window] quit\n\n")
    'face 'health-chart-dim)))

(defun health-chart-dashboard--find-marker (marker)
  "Position of the first row of MARKER in this buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (when-let* ((match (text-property-search-forward 'health-chart-marker marker #'equal)))
      (prop-match-beginning match))))

(defun health-chart-dashboard--render ()
  "Redraw the dashboard from the fetched data, keeping point's marker."
  (let ((marker (get-text-property (point) 'health-chart-marker))
        (inhibit-read-only t)
        (ms (health-chart-dashboard--visible))
        (props (health-chart-dashboard--props)))
    (erase-buffer)
    (insert (health-chart-dashboard--header))
    (cond
     (health-chart-dashboard--error
      (insert (propertize (format "Source error: %s\n" health-chart-dashboard--error)
                          'face 'health-chart-out-of-range)
              (propertize "Fix the source (M-x customize-group RET health-charts) and press g.\n"
                          'face 'health-chart-dim)))
     ((null ms)
      (insert (propertize health-chart-empty-text 'face 'health-chart-dim) "\n"))
     (t
      (insert (health-chart-plot 'table ms :backend 'text :person health-chart-dashboard--person)
              "\n")
      (health-chart-dashboard--insert-cohort props)
      (dolist (kind health-chart-dashboard-sections)
        (insert "\n")
        (apply #'health-chart-plot-insert kind ms
               :width (max 60 (min 110 (- (window-body-width) 2))) props)
        (insert "\n"))))
    (goto-char (point-min))
    (when-let* ((pos (and marker (health-chart-dashboard--find-marker marker))))
      (goto-char pos))))

(defun health-chart-dashboard--cohort-values ()
  "The selected cohort evaluated over the fetched data (no extra fetch)."
  (health-chart-cohort-evaluate health-chart-dashboard--cohort health-chart-dashboard--data
                                :person health-chart-dashboard--person))

(defun health-chart-dashboard--insert-cohort (props)
  "Insert the selected cohort's sections with chart PROPS, or its error."
  (when health-chart-dashboard--cohort
    (condition-case err
        (let ((values (health-chart-dashboard--cohort-values)))
          (dolist (kind health-chart-dashboard-cohort-sections)
            (insert "\n")
            (apply #'health-chart-plot-insert kind values
                   :width (max 60 (min 110 (- (window-body-width) 2))) props)
            (insert "\n")))
      (health-chart-error
       (insert "\n" (propertize (format "Cohort error: %s\n" (cadr err))
                                'face 'health-chart-out-of-range))))))

;; -----------------------------------------------------------------------
;; Commands
;; -----------------------------------------------------------------------

;;;###autoload
(defun health-chart-dashboard (&optional person)
  "Open the biomarker dashboard, for PERSON when given.
Interactively, a prefix argument prompts for the person."
  (interactive
   (list (when current-prefix-arg
           (read-string "Person: " nil nil health-chart-default-person))))
  (let ((buf (get-buffer-create health-chart-dashboard-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'health-chart-dashboard-mode)
        (health-chart-dashboard-mode)
        (setq health-chart-dashboard--backend health-chart-dashboard-backend
              health-chart-dashboard--cohort health-chart-dashboard-cohort
              health-chart-dashboard--ref health-chart-show-ref-range
              health-chart-dashboard--optimal health-chart-show-optimal-range))
      (when (and person (not (string-empty-p person)))
        (setq health-chart-dashboard--person person))
      (health-chart-dashboard--fetch)
      (health-chart-dashboard--render))
    (unless noninteractive (pop-to-buffer buf))
    buf))

;;;###autoload
(defalias 'health-charts #'health-chart-dashboard)

(defun health-chart-dashboard-refresh ()
  "Refetch from the source and redraw."
  (interactive)
  (health-chart-dashboard--fetch)
  (health-chart-dashboard--render))

(defun health-chart-dashboard-select-person (person)
  "Show PERSON's measurements; with an empty PERSON, stay on the current one."
  (interactive
   (list (completing-read "Person: " health-chart-dashboard--persons nil nil nil nil
                          health-chart-dashboard--person)))
  (unless (string-empty-p person)
    (setq health-chart-dashboard--person person))
  (health-chart-dashboard-refresh))

(defun health-chart-dashboard--categories ()
  "Categories present in the fetched data."
  (seq-uniq (mapcar #'health-chart-marker-category health-chart-dashboard--data)))

(defun health-chart-dashboard-select-category (category)
  "Show only markers in CATEGORY (\"all\" for every marker)."
  (interactive
   (list (completing-read "Category: " (cons "all" (health-chart-dashboard--categories))
                          nil t nil nil "all")))
  (setq health-chart-dashboard--category (unless (member category '("all" "")) category))
  (health-chart-dashboard--render))

(defun health-chart-dashboard-select-cohort (cohort)
  "Show indicator COHORT below the table (\"none\" to hide it).
COHORT names an entry of `health-chart-indicator-cohorts'."
  (interactive
   (list (completing-read "Cohort: " (cons "none" (mapcar #'symbol-name (health-chart-cohort-names)))
                          nil t nil nil (if health-chart-dashboard--cohort
                                            (symbol-name health-chart-dashboard--cohort)
                                          "none"))))
  (let ((name (unless (member (format "%s" cohort) '("none" ""))
                (health-chart--cohort-symbol cohort))))
    (when name (health-chart--cohort name))
    (setq health-chart-dashboard--cohort name))
  (health-chart-dashboard--render))

(defun health-chart-dashboard-cohort-panel ()
  "Show the selected cohort as a cohort panel in its own buffer."
  (interactive)
  (unless health-chart-dashboard--cohort
    (user-error "No cohort selected; press %s to pick one"
                (substitute-command-keys "\\<health-chart-dashboard-mode-map>\\[health-chart-dashboard-select-cohort]")))
  (health-chart-dashboard--view 'cohort (health-chart-dashboard--cohort-values)
                                :buffer (format "*health-chart: %s*" health-chart-dashboard--cohort)))

(defun health-chart-dashboard-toggle-backend ()
  "Flip the dashboard sections between text and an image backend."
  (interactive)
  (let ((kind (or (car health-chart-dashboard-sections) 'bullet)))
    (setq health-chart-dashboard--backend
          (health-chart--toggled-backend kind health-chart-dashboard--backend))
    (when (eq (health-chart--usable-backend health-chart-dashboard--backend kind) 'text)
      (unless (eq health-chart-dashboard--backend 'text)
        (message "This frame cannot show images; showing text"))))
  (health-chart-dashboard--render))

(defun health-chart-dashboard-toggle-ref ()
  "Show or hide reference-range bands."
  (interactive)
  (setq health-chart-dashboard--ref (not health-chart-dashboard--ref))
  (health-chart-dashboard--render))

(defun health-chart-dashboard-toggle-optimal ()
  "Show or hide optimal-range bands."
  (interactive)
  (setq health-chart-dashboard--optimal (not health-chart-dashboard--optimal))
  (health-chart-dashboard--render))

(defun health-chart-dashboard--marker-at-point ()
  "The marker on the current line, or signal a user error."
  (or (get-text-property (point) 'health-chart-marker)
      (get-text-property (line-beginning-position) 'health-chart-marker)
      (user-error "No marker on this line")))

(defun health-chart-dashboard--view (kind data &rest props)
  "Show KIND of DATA with PROPS in its own buffer, with this dashboard's state."
  (apply #'health-chart-plot-view kind data
         (append props (health-chart--plist-drop (health-chart-dashboard--props) :person))))

(defun health-chart-dashboard-open ()
  "Open the time series of the marker at point."
  (interactive)
  (let ((marker (health-chart-dashboard--marker-at-point)))
    (health-chart-dashboard--view
     'timeseries (health-chart-filter health-chart-dashboard--data :marker marker)
     :marker marker :person health-chart-dashboard--person
     :buffer (format "*health-chart: %s*" (health-chart-marker-label marker)))))

(defun health-chart-dashboard-compare ()
  "Overlay the marker at point for every person."
  (interactive)
  (let* ((marker (health-chart-dashboard--marker-at-point))
         (ms (health-chart-source-trend :marker marker :person nil)))
    (health-chart-dashboard--view
     'compare ms :marker marker
     :buffer (format "*health-chart: %s compare*" (health-chart-marker-label marker)))))

(defun health-chart-dashboard-panel ()
  "Show the visible markers as small multiples."
  (interactive)
  (health-chart-dashboard--view 'panel (health-chart-dashboard--visible)
                                :person health-chart-dashboard--person
                                :buffer "*health-chart: panel*"))

(defun health-chart-dashboard-delta ()
  "Show each visible marker's change between the two latest draws."
  (interactive)
  (health-chart-dashboard--view 'delta (health-chart-dashboard--visible)
                                :person health-chart-dashboard--person
                                :buffer "*health-chart: change*"))

(defun health-chart-dashboard--move (direction)
  "Move point to the next marker row in DIRECTION (1 or -1)."
  (let ((start (point)) found)
    (forward-line direction)
    (while (and (not found) (not (if (> direction 0) (eobp) (bobp))))
      (if (get-text-property (point) 'health-chart-marker)
          (setq found t)
        (forward-line direction)))
    (unless (or found (get-text-property (point) 'health-chart-marker))
      (goto-char start))))

(defun health-chart-dashboard-next ()
  "Move to the next marker row."
  (interactive)
  (health-chart-dashboard--move 1))

(defun health-chart-dashboard-previous ()
  "Move to the previous marker row."
  (interactive)
  (health-chart-dashboard--move -1))

(provide 'health-chart-dashboard)
;;; health-chart-dashboard.el ends here
