# Gene-to-lab links

`health-chart-gene-lab-links` (in `health-chart-genetics.el`) says which
lab markers are commonly read next to a gene.  The `health-genetics-labs`
Org block prints each gene's call from genetics.el beside those markers'
latest values and charts.

**Informational only, not medical advice.**  A link names markers that
are often reviewed together with a gene.  It does not say what a
genotype means for a person, and a genotype does not diagnose anything.
Discuss results with a clinician.

| gene | SNPs | linked markers | why they are read together |
|---|---|---|---|
| APOE | rs429358, rs7412 (read as the ε2/ε3/ε4 haplotype) | LDL-C, ApoB, Lp(a), total cholesterol | APOE carries cholesterol in the blood. Its alleles are associated with differences in LDL-C and ApoB. |
| MTHFR | rs1801133 (C677T), rs1801131 (A1298C) | homocysteine, folate, vitamin B12 | MTHFR helps process folate. These variants lower enzyme activity and are associated with higher homocysteine when folate or B12 is low. |
| HFE | rs1800562 (C282Y), rs1799945 (H63D) | ferritin, iron, transferrin saturation | HFE helps regulate iron uptake. These variants are associated with higher iron stores. |
| LCT | rs4988235 | none | Associated with lactase persistence into adulthood. Relevant to dietary lactose tolerance only. |
| F5 | rs6025 (factor V Leiden) | none in standard panels | Associated with a higher tendency to form blood clots. It is read from genetic or coagulation testing. |
| CYP2C19 | rs4244285 (*2) | none (pharmacogenomic) | Associated with reduced metabolism of some medicines, such as clopidogrel. |

## How a call is read

- Genotypes are plus-strand, as in 23andMe-format files.
- APOE: a C at rs429358 marks ε4 and a T at rs7412 marks ε2; anything
  else is ε3.  One of each reads as ε2/ε4.  The rare ε1/ε3 gives the
  same unphased calls (`health-chart-genetics-apoe-haplotype`).
- The call source is either *observed* (read from the kit) or *inferred
  reference* (genetics.el filled in the reference genotype at a position
  the kit does not report).  If the SNPs of one gene differ, each SNP
  shows its own source.

## Sources

- APOE: [MedlinePlus Genetics: APOE gene](https://medlineplus.gov/genetics/gene/apoe/);
  [dbSNP rs429358](https://www.ncbi.nlm.nih.gov/snp/rs429358),
  [dbSNP rs7412](https://www.ncbi.nlm.nih.gov/snp/rs7412);
  [SNPedia: APOE](https://www.snpedia.com/index.php/APOE).
- MTHFR: [MedlinePlus Genetics: MTHFR gene](https://medlineplus.gov/genetics/gene/mthfr/);
  [SNPedia rs1801133](https://www.snpedia.com/index.php/Rs1801133),
  [SNPedia rs1801131](https://www.snpedia.com/index.php/Rs1801131).
- HFE: [MedlinePlus Genetics: HFE gene](https://medlineplus.gov/genetics/gene/hfe/);
  [MedlinePlus Genetics: hereditary hemochromatosis](https://medlineplus.gov/genetics/condition/hereditary-hemochromatosis/);
  [SNPedia rs1800562](https://www.snpedia.com/index.php/Rs1800562),
  [SNPedia rs1799945](https://www.snpedia.com/index.php/Rs1799945).
- LCT: [MedlinePlus Genetics: lactose intolerance](https://medlineplus.gov/genetics/condition/lactose-intolerance/);
  [SNPedia rs4988235](https://www.snpedia.com/index.php/Rs4988235).
- F5: [MedlinePlus Genetics: F5 gene](https://medlineplus.gov/genetics/gene/f5/);
  [MedlinePlus Genetics: factor V Leiden thrombophilia](https://medlineplus.gov/genetics/condition/factor-v-leiden-thrombophilia/);
  [SNPedia rs6025](https://www.snpedia.com/index.php/Rs6025).
- CYP2C19: [MedlinePlus Genetics: CYP2C19 gene](https://medlineplus.gov/genetics/gene/cyp2c19/);
  [CPIC guideline for clopidogrel and CYP2C19](https://cpicpgx.org/guidelines/guideline-for-clopidogrel-and-cyp2c19/);
  [SNPedia rs4244285](https://www.snpedia.com/index.php/Rs4244285).

## Changing the table

Every entry has the form `(GENE :rsids RSIDS [:call apoe] [:markers
MARKERS] [:note NOTE] :rationale TEXT :source (TITLE . URL))`.  A marker
can be a list of alternative spellings, for example
`("vitamin-b12" "b12")`; the first one is shown.  Add or edit entries
with `setopt`/Customize, then check them with
`(health-chart-genetics-doctor-checks)`.  Keep rationales to one
informational sentence and cite a source.
