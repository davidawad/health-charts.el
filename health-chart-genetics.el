;;; health-chart-genetics.el --- Genetics-to-labs links for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Which lab markers are worth reading next to which genotypes.  The
;; link table `health-chart-gene-lab-links' is DATA: one entry per gene
;; names its SNPs, the markers it relates to, a one-line rationale and
;; the source it cites (docs/gene-lab-links.md lists them all).  The
;; language stays informational: a link says what is commonly reviewed
;; together, never what a genotype means for a person.
;;
;; Genotypes come from genetics.el, a soft dependency: this file never
;; loads it.  `health-chart-genetics-functions' names the two public
;; genetics.el functions used (find a kit, read one SNP's call); when
;; they are not defined the callers print a note instead.
;;
;;   pure       `health-chart-genetics-links' (resolve gene names),
;;              `health-chart-genetics-normalize-call',
;;              `health-chart-genetics-apoe-haplotype',
;;              `health-chart-genetics-calls-explain' (the plan).
;;   effectful  `health-chart-genetics-calls' (asks genetics.el).
;;   health     `health-chart-genetics-doctor-checks'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)

(define-error 'health-chart-genetics-error
  "health-chart: genetics error" 'health-chart-error)

(defcustom health-chart-gene-lab-links
  '(("APOE"
     :rsids ("rs429358" "rs7412") :call apoe
     :markers ("ldl-c" "apob" "lpa" ("total-cholesterol" "cholesterol-total"))
     :rationale "APOE carries cholesterol in the blood; its ε2/ε3/ε4 alleles (rs429358, rs7412) are associated with differences in LDL-C and ApoB, so the lipid markers are often read alongside it."
     :source ("MedlinePlus Genetics: APOE" . "https://medlineplus.gov/genetics/gene/apoe/"))
    ("MTHFR"
     :rsids ("rs1801133" "rs1801131")
     :markers ("homocysteine" "folate" ("vitamin-b12" "b12"))
     :rationale "MTHFR helps process folate; the common C677T (rs1801133) and A1298C (rs1801131) variants lower enzyme activity and are associated with higher homocysteine when folate or B12 is low."
     :source ("MedlinePlus Genetics: MTHFR" . "https://medlineplus.gov/genetics/gene/mthfr/"))
    ("HFE"
     :rsids ("rs1800562" "rs1799945")
     :markers ("ferritin" "iron" "transferrin-saturation")
     :rationale "HFE helps regulate iron uptake; C282Y (rs1800562) and H63D (rs1799945) are associated with higher iron stores, which ferritin, serum iron and transferrin saturation describe."
     :source ("MedlinePlus Genetics: HFE" . "https://medlineplus.gov/genetics/gene/hfe/"))
    ("LCT"
     :rsids ("rs4988235")
     :note "Relevant to dietary lactose tolerance only; no standard lab marker is linked."
     :rationale "rs4988235, upstream of LCT, is associated with lactase persistence into adulthood."
     :source ("MedlinePlus Genetics: lactose intolerance"
              . "https://medlineplus.gov/genetics/condition/lactose-intolerance/"))
    ("F5"
     :rsids ("rs6025")
     :note "No marker in standard lab panels reflects it; it is read from genetic or coagulation testing."
     :rationale "rs6025 is factor V Leiden, associated with a higher tendency to form blood clots."
     :source ("MedlinePlus Genetics: F5" . "https://medlineplus.gov/genetics/gene/f5/"))
    ("CYP2C19"
     :rsids ("rs4244285")
     :note "Pharmacogenomic: it bears on how some medicines are processed, with no lab marker."
     :rationale "rs4244285 (CYP2C19*2) is associated with reduced metabolism of some medicines, such as clopidogrel."
     :source ("MedlinePlus Genetics: CYP2C19" . "https://medlineplus.gov/genetics/gene/cyp2c19/")))
  "Genes and the lab markers commonly read next to them.
Each entry is (GENE :rsids RSIDS [:call apoe] [:markers MARKERS]
[:note NOTE] :rationale TEXT :source (TITLE . URL)).

RSIDS are the SNPs read from the genetics kit.  :call apoe summarises
rs429358 and rs7412 as an APOE haplotype (see
`health-chart-genetics-apoe-haplotype'); otherwise each SNP's genotype
is shown.  MARKERS are lab marker ids; an element may be a list of
spellings of one marker, the first being the one shown.  A gene with
no MARKERS prints its NOTE as a single informational line.  RATIONALE
is one sentence and SOURCE the page it is drawn from;
docs/gene-lab-links.md has the full citations.

Every link is informational: it names markers often reviewed together
with a gene, never a diagnosis."
  :type '(alist :key-type string :value-type plist)
  :group 'health-charts)

(declare-function genetics-org-kit "genetics-org" (params))
(declare-function genetics-kit-resolve "genetics-annotate" (kit rsid))
(declare-function genetics-snp-genotype "genetics-core" (snp))
(declare-function genetics-snp-inferred-p "genetics-core" (snp))

(defun health-chart-genetics-kit-via-genetics (name file)
  "The genetics.el kit named NAME, else the one loaded from FILE.
A loaded kit called NAME wins; otherwise FILE is opened (or reused)
through `genetics-org-kit'."
  (or (and name (ignore-errors (genetics-org-kit (list :kit name))))
      (genetics-org-kit (if file (list :file file) (list :kit name)))))

(defun health-chart-genetics-genotype-via-genetics (kit rsid)
  "RSID's call in KIT through genetics.el's `genetics-kit-resolve'.
Kits without rsids resolve by position on their build; variant-only WGS
kits fall back to an inferred homozygous-reference call."
  (when-let* ((snp (genetics-kit-resolve kit rsid)))
    (list :genotype (genetics-snp-genotype snp)
          :source (if (genetics-snp-inferred-p snp) 'inferred 'observed))))

(defconst health-chart-genetics--wrapped
  '((health-chart-genetics-kit-via-genetics . genetics-org-kit)
    (health-chart-genetics-genotype-via-genetics . genetics-kit-resolve))
  "The genetics.el function each bundled wrapper needs.")

(defcustom health-chart-genetics-functions
  '(:kit health-chart-genetics-kit-via-genetics
    :genotype health-chart-genetics-genotype-via-genetics)
  "The functions genetics-to-labs links call to read genetics.el kits.
A plist: :kit is called as (FN NAME FILE) with the block's :kit name
and :file kit path (either may be nil) and returns a kit; :genotype is
called as (FN KIT RSID) and returns that SNP's call: a genotype string
such as \"CT\", nil for no call, or a plist (:genotype STRING :source
observed|inferred).  The defaults wrap genetics.el's `genetics-org-kit'
and `genetics-kit-resolve'.  genetics.el is never loaded from here."
  :type '(plist :key-type symbol :value-type function)
  :group 'health-charts)

(defconst health-chart-genetics-disclaimer
  "Informational only, not medical advice: these links show which lab markers are commonly read next to a gene; discuss results with a clinician."
  "The line every genetics-to-labs output ends with.")

(defconst health-chart-genetics-sources
  '((observed . "observed") (inferred . "inferred reference"))
  "Call sources and how they read.")

;; -----------------------------------------------------------------------
;; Pure: the link table
;; -----------------------------------------------------------------------

(defun health-chart-genetics-gene-names ()
  "The genes in `health-chart-gene-lab-links', in table order."
  (mapcar #'car health-chart-gene-lab-links))

(defun health-chart-genetics-link (gene)
  "GENE's link entry as a plist with :gene, or signal.
GENE is a string or symbol, matched case-insensitively."
  (let* ((name (format "%s" gene))
         (entry (seq-find (lambda (e) (string= (upcase (car e)) (upcase name)))
                          health-chart-gene-lab-links)))
    (unless entry
      (signal 'health-chart-genetics-error
              (list (format "unknown gene %s; use one of %s, or add it to `health-chart-gene-lab-links'"
                            name (string-join (health-chart-genetics-gene-names) " "))
                    :code "unknown_gene" :gene name)))
    (cons :gene (cons (car entry) (cdr entry)))))

(defun health-chart-genetics-links (&optional genes)
  "The link entries of GENES (default: every gene), each with :gene."
  (mapcar #'health-chart-genetics-link (or genes (health-chart-genetics-gene-names))))

(defun health-chart-genetics-marker-id (marker)
  "The id shown for link MARKER (a string, or a list of spellings)."
  (if (consp marker) (car marker) marker))

(defun health-chart-genetics-marker-spellings (marker)
  "Every spelling of link MARKER, as a list."
  (if (consp marker) marker (list marker)))

;; -----------------------------------------------------------------------
;; Pure: calls
;; -----------------------------------------------------------------------

(defun health-chart-genetics--source (v)
  "Call source V as observed or inferred (anything mentioning infer)."
  (if (string-match-p "infer" (format "%s" (or v ""))) 'inferred 'observed))

(defun health-chart-genetics-normalize-call (raw)
  "A genetics.el call RAW as (:genotype STRING :source SOURCE), or nil.
RAW is a genotype string, a plist with :genotype (or :call) and
:source, or nil.  No-calls (\"--\", \"00\", empty) become nil; SOURCE is
observed unless the call says it was inferred."
  (let* ((plist (and (consp raw) (keywordp (car raw))))
         (genotype (cond ((stringp raw) raw)
                         (plist (or (plist-get raw :genotype) (plist-get raw :call)))))
         (genotype (and (stringp genotype) (upcase (string-trim genotype)))))
    (when (and genotype (string-match-p "\\`[ACGTDI]+\\'" genotype))
      (list :genotype genotype
            :source (health-chart-genetics--source (and plist (plist-get raw :source)))))))

(defun health-chart-genetics-apoe-haplotype (rs429358 rs7412)
  "The APOE haplotype from genotypes RS429358 and RS7412, or nil.
Plus-strand alleles: rs429358 C marks ε4, rs7412 T marks ε2, neither
is ε3.  Returns a string such as \"ε3/ε4\"; nil when either call is
missing or the pair does not resolve.  One C and one T reads as ε2/ε4
\(ε1/ε3 gives the same unphased calls and is rare)."
  (when (and (stringp rs429358) (stringp rs7412)
             (= (length rs429358) 2) (= (length rs7412) 2))
    (let ((e4 (cl-count ?C rs429358)) (e2 (cl-count ?T rs7412)))
      (when (<= (+ e4 e2) 2)
        (string-join (append (make-list e2 "ε2") (make-list (- 2 e2 e4) "ε3")
                             (make-list e4 "ε4"))
                     "/")))))

(defun health-chart-genetics--summary (link snps)
  "Summarise LINK's genotypes SNPS, ((RSID . CALL-OR-NIL)...).
A plist: :calls SNPS :haplotype (for :call apoe) :called (non-nil when
any SNP has a call) :source (observed, inferred or mixed)."
  (let* ((called (seq-filter #'cdr snps))
         (sources (seq-uniq (mapcar (lambda (c) (plist-get (cdr c) :source)) called))))
    (list :gene (plist-get link :gene) :calls snps :called (and called t)
          :haplotype (when (eq (plist-get link :call) 'apoe)
                       (health-chart-genetics-apoe-haplotype
                        (plist-get (cdr (assoc "rs429358" snps)) :genotype)
                        (plist-get (cdr (assoc "rs7412" snps)) :genotype)))
          :source (cond ((null sources) nil) ((cdr sources) 'mixed) (t (car sources))))))

;; -----------------------------------------------------------------------
;; genetics.el, softly
;; -----------------------------------------------------------------------

(defun health-chart-genetics--fn (role)
  "The function `health-chart-genetics-functions' names for ROLE."
  (plist-get health-chart-genetics-functions role))

(defun health-chart-genetics-available-p ()
  "Non-nil when the genetics.el functions in use are defined."
  (seq-every-p (lambda (role)
                 (let ((fn (health-chart-genetics--fn role)))
                   (and (fboundp fn)
                        (fboundp (or (alist-get fn health-chart-genetics--wrapped) fn)))))
               '(:kit :genotype)))

(defun health-chart-genetics-calls-explain (kit file &optional genes)
  "The plan of `health-chart-genetics-calls' for KIT, FILE and GENES.  Pure.
A plist: :available (whether genetics.el's functions are defined) :kit
\(the call finding the kit) :genotype (the function reading each SNP)
:genes (each (:gene :rsids :call)).  Calls nothing."
  (list :available (health-chart-genetics-available-p)
        :kit (list (health-chart-genetics--fn :kit) kit file)
        :genotype (health-chart-genetics--fn :genotype)
        :genes (mapcar (lambda (l) (list :gene (plist-get l :gene) :rsids (plist-get l :rsids)
                                         :call (or (plist-get l :call) 'genotype)))
                       (health-chart-genetics-links genes))))

(defun health-chart-genetics-calls (kit file &optional genes)
  "Read the genotypes of GENES from genetics kit KIT (a name) or FILE (a path).
GENES default to every linked gene.  Returns one summary plist per gene
\(:gene :calls ((RSID . CALL)...) :called :haplotype :source); see
`health-chart-genetics-normalize-call' for CALL.  Signals
`health-chart-genetics-error' when genetics.el is not loaded or finds
no kit.  The pure plan is `health-chart-genetics-calls-explain'."
  (let ((links (health-chart-genetics-links genes)))
    (unless (health-chart-genetics-available-p)
      (signal 'health-chart-genetics-error
              (list (format "genetics.el is not loaded (%s and %s are undefined); load it, or point `health-chart-genetics-functions' at its API"
                            (health-chart-genetics--fn :kit) (health-chart-genetics--fn :genotype))
                    :code "genetics_missing")))
    (let ((k (condition-case err
                 (funcall (health-chart-genetics--fn :kit) kit file)
               (error (signal 'health-chart-genetics-error
                              (list (format "genetics.el could not open kit %s: %s; check :kit or :file"
                                            (or kit file "(default)") (error-message-string err))
                                    :code "genetics_kit"))))))
      (unless k
        (signal 'health-chart-genetics-error
                (list (format "genetics.el has no kit %s; load it or set :file to the kit file"
                              (or kit file "(default)"))
                      :code "genetics_kit")))
      (mapcar (lambda (link)
                (health-chart-genetics--summary
                 link
                 (mapcar (lambda (rsid)
                           (cons rsid (health-chart-genetics-normalize-call
                                       (funcall (health-chart-genetics--fn :genotype) k rsid))))
                         (plist-get link :rsids))))
              links))))

;; -----------------------------------------------------------------------
;; Words
;; -----------------------------------------------------------------------

(defun health-chart-genetics-source-label (source)
  "SOURCE (observed, inferred, mixed) as words."
  (or (cdr (assq source health-chart-genetics-sources)) (format "%s" source)))

(defun health-chart-genetics-call-text (summary)
  "Describe the genotypes in SUMMARY in words.
For example \"ε3/ε4 haplotype (rs429358 TC, rs7412 CC; observed)\"."
  (let* ((mixed (eq (plist-get summary :source) 'mixed))
         (snps (mapconcat
                (lambda (c)
                  (if (cdr c)
                      (format "%s %s%s" (car c) (plist-get (cdr c) :genotype)
                              (if mixed (format " %s" (health-chart-genetics-source-label
                                                       (plist-get (cdr c) :source)))
                                ""))
                    (format "%s no call" (car c))))
                (plist-get summary :calls) ", "))
         (detail (if mixed snps
                   (format "%s; %s" snps (health-chart-genetics-source-label
                                          (plist-get summary :source))))))
    (if (plist-get summary :haplotype)
        (format "%s haplotype (%s)" (plist-get summary :haplotype) detail)
      (format "%s" detail))))

;; -----------------------------------------------------------------------
;; Health
;; -----------------------------------------------------------------------

(defun health-chart-genetics-doctor-checks ()
  "Doctor rows for genetics-to-labs: the link table and genetics.el.
Rows are (:name :status pass|fail|skip :detail :remediation).  Never
loads genetics.el."
  (let ((bad (seq-remove (lambda (e) (and (stringp (car e)) (plist-get (cdr e) :rsids)
                                          (plist-get (cdr e) :rationale)
                                          (or (plist-get (cdr e) :markers) (plist-get (cdr e) :note))))
                         health-chart-gene-lab-links)))
    (list
     (if bad
         (list :name "gene-lab-links" :status 'fail
               :detail (format "malformed entries: %s" (mapconcat (lambda (e) (format "%s" (car e))) bad " "))
               :remediation "give each entry a gene name, :rsids, :rationale and :markers or :note")
       (list :name "gene-lab-links" :status 'pass
             :detail (format "%d genes linked" (length health-chart-gene-lab-links))))
     (if (health-chart-genetics-available-p)
         (list :name "genetics.el" :status 'pass
               :detail (format "%s and %s are defined" (health-chart-genetics--fn :kit)
                               (health-chart-genetics--fn :genotype)))
       (list :name "genetics.el" :status 'skip
             :detail "genetics.el is not loaded; genetics blocks print a note"
             :remediation "load genetics.el, or point `health-chart-genetics-functions' at its API")))))

(provide 'health-chart-genetics)
;;; health-chart-genetics.el ends here
