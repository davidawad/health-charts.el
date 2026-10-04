# health-chart: heatmap chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,540 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart heatmap: markers (rows) by draw dates (columns), each
# cell colored by status with its glyph and value drawn in it (glyph and
# word in the key).  The backend has already chosen the terminal, the
# output and a tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	x_index	y_index	date_label	cell_label	out
alex	ldl-c	LDL-C	2021-11-08	162	mg/dL	162 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	1	1	Nov 2021	▲ 162	5
alex	ldl-c	LDL-C	2022-05-16	151	mg/dL	151 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	2	1	May 2022	▲ 151	5
alex	ldl-c	LDL-C	2022-11-14	138	mg/dL	138 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	3	1	Nov 2022	▲ 138	5
alex	ldl-c	LDL-C	2023-06-05	121	mg/dL	121 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	4	1	Jun 2023	▲ 121	5
alex	ldl-c	LDL-C	2024-01-15	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	5	1	Jan 2024	▲ 104	5
alex	ldl-c	LDL-C	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	6	1	Aug 2024	◐ 92	5
alex	ldl-c	LDL-C	2025-03-10	84	mg/dL	84 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	7	1	Mar 2025	◐ 84	5
alex	ldl-c	LDL-C	2025-09-15	76	mg/dL	76 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	8	1	Sep 2025	◐ 76	5
alex	hdl-c	HDL-C	2021-11-08	38	mg/dL	38 mg/dL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	40	NaN	60	NaN	1	2	Nov 2021	▼ 38	1
alex	hdl-c	HDL-C	2022-05-16	41	mg/dL	41 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	2	May 2022	◐ 41	1
alex	hdl-c	HDL-C	2022-11-14	44	mg/dL	44 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	3	2	Nov 2022	◐ 44	1
alex	hdl-c	HDL-C	2023-06-05	47	mg/dL	47 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	4	2	Jun 2023	◐ 47	1
alex	hdl-c	HDL-C	2024-01-15	52	mg/dL	52 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	5	2	Jan 2024	◐ 52	1
alex	hdl-c	HDL-C	2024-08-12	55	mg/dL	55 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	6	2	Aug 2024	◐ 55	1
alex	hdl-c	HDL-C	2025-03-10	58	mg/dL	58 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	7	2	Mar 2025	◐ 58	1
alex	hdl-c	HDL-C	2025-09-15	61	mg/dL	61 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	40	NaN	60	NaN	8	2	Sep 2025	● 61	1
alex	triglycerides	Triglycerides	2021-11-08	212	mg/dL	212 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	150	NaN	100	1	3	Nov 2021	▲ 212	3
alex	triglycerides	Triglycerides	2022-05-16	188	mg/dL	188 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	150	NaN	100	2	3	May 2022	▲ 188	3
alex	triglycerides	Triglycerides	2022-11-14	160	mg/dL	160 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	150	NaN	100	3	3	Nov 2022	▲ 160	3
alex	triglycerides	Triglycerides	2023-06-05	138	mg/dL	138 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	150	NaN	100	4	3	Jun 2023	◐ 138	3
alex	triglycerides	Triglycerides	2024-01-15	121	mg/dL	121 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	150	NaN	100	5	3	Jan 2024	◐ 121	3
alex	triglycerides	Triglycerides	2024-08-12	104	mg/dL	104 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	150	NaN	100	6	3	Aug 2024	◐ 104	3
alex	triglycerides	Triglycerides	2025-03-10	96	mg/dL	96 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	150	NaN	100	7	3	Mar 2025	● 96	3
alex	triglycerides	Triglycerides	2025-09-15	88	mg/dL	88 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	150	NaN	100	8	3	Sep 2025	● 88	3
alex	apob	ApoB	2021-11-08	128	mg/dL	128 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	1	4	Nov 2021	▲ 128	4
alex	apob	ApoB	2022-05-16	120	mg/dL	120 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	2	4	May 2022	▲ 120	4
alex	apob	ApoB	2022-11-14	111	mg/dL	111 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	3	4	Nov 2022	▲ 111	4
alex	apob	ApoB	2023-06-05	98	mg/dL	98 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	4	4	Jun 2023	▲ 98	4
alex	apob	ApoB	2024-01-15	88	mg/dL	88 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	90	NaN	80	5	4	Jan 2024	◐ 88	4
alex	apob	ApoB	2024-08-12	81	mg/dL	81 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	90	NaN	80	6	4	Aug 2024	◐ 81	4
alex	apob	ApoB	2025-03-10	76	mg/dL	76 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	90	NaN	80	7	4	Mar 2025	● 76	4
alex	apob	ApoB	2025-09-15	72	mg/dL	72 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	90	NaN	80	8	4	Sep 2025	● 72	4
alex	lpa	Lp(a)	2021-11-08	142	nmol/L	142 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	1	5	Nov 2021	▲ 142	8
alex	lpa	Lp(a)	2022-05-16	148	nmol/L	148 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	2	5	May 2022	▲ 148	8
alex	lpa	Lp(a)	2022-11-14	139	nmol/L	139 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	3	5	Nov 2022	▲ 139	8
alex	lpa	Lp(a)	2023-06-05	151	nmol/L	151 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	4	5	Jun 2023	▲ 151	8
alex	lpa	Lp(a)	2024-01-15	145	nmol/L	145 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	5	Jan 2024	▲ 145	8
alex	lpa	Lp(a)	2024-08-12	140	nmol/L	140 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	6	5	Aug 2024	▲ 140	8
alex	lpa	Lp(a)	2025-03-10	149	nmol/L	149 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	7	5	Mar 2025	▲ 149	8
alex	lpa	Lp(a)	2025-09-15	144	nmol/L	144 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	8	5	Sep 2025	▲ 144	8
alex	hba1c	HbA1c	2021-11-08	5.9	%	5.9 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	1	6	Nov 2021	▲ 5.9	3
alex	hba1c	HbA1c	2022-05-16	5.8	%	5.8 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	2	6	May 2022	▲ 5.8	3
alex	hba1c	HbA1c	2022-11-14	5.7	%	5.7 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	3	6	Nov 2022	▲ 5.7	3
alex	hba1c	HbA1c	2023-06-05	5.6	%	5.6 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	4	6	Jun 2023	◐ 5.6	3
alex	hba1c	HbA1c	2024-01-15	5.5	%	5.5 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	5	6	Jan 2024	◐ 5.5	3
alex	hba1c	HbA1c	2024-08-12	5.4	%	5.4 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	6	6	Aug 2024	◐ 5.4	3
alex	hba1c	HbA1c	2025-03-10	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	7	6	Mar 2025	● 5.3	3
alex	hba1c	HbA1c	2025-09-15	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	8	6	Sep 2025	● 5.3	3
alex	glucose	Glucose	2021-11-08	108	mg/dL	108 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	1	7	Nov 2021	▲ 108	3
alex	glucose	Glucose	2022-05-16	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	2	7	May 2022	▲ 104	3
alex	glucose	Glucose	2022-11-14	101	mg/dL	101 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	3	7	Nov 2022	▲ 101	3
alex	glucose	Glucose	2023-06-05	97	mg/dL	97 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	4	7	Jun 2023	◐ 97	3
alex	glucose	Glucose	2024-01-15	94	mg/dL	94 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	5	7	Jan 2024	◐ 94	3
alex	glucose	Glucose	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	6	7	Aug 2024	◐ 92	3
alex	glucose	Glucose	2025-03-10	96	mg/dL	96 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	7	7	Mar 2025	◐ 96	3
alex	glucose	Glucose	2025-09-15	89	mg/dL	89 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	70	99	72	90	8	7	Sep 2025	● 89	3
alex	hscrp	hs-CRP	2021-11-08	4.2	mg/L	4.2 mg/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	3.0	NaN	1.0	1	8	Nov 2021	▲ 4.2	2
alex	hscrp	hs-CRP	2022-05-16	3.6	mg/L	3.6 mg/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	3.0	NaN	1.0	2	8	May 2022	▲ 3.6	2
alex	hscrp	hs-CRP	2022-11-14	2.8	mg/L	2.8 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	3	8	Nov 2022	◐ 2.8	2
alex	hscrp	hs-CRP	2023-06-05	2.1	mg/L	2.1 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	4	8	Jun 2023	◐ 2.1	2
alex	hscrp	hs-CRP	2024-01-15	1.6	mg/L	1.6 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	5	8	Jan 2024	◐ 1.6	2
alex	hscrp	hs-CRP	2024-08-12	1.2	mg/L	1.2 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	6	8	Aug 2024	◐ 1.2	2
alex	hscrp	hs-CRP	2025-03-10	0.9	mg/L	0.9 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	7	8	Mar 2025	● 0.9	2
alex	hscrp	hs-CRP	2025-09-15	0.8	mg/L	0.8 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	8	8	Sep 2025	● 0.8	2
alex	vitamin-d	Vitamin D	2021-11-08	22	ng/mL	22 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	1	9	Nov 2021	▼ 22	2
alex	vitamin-d	Vitamin D	2022-05-16	26	ng/mL	26 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	2	9	May 2022	▼ 26	2
alex	vitamin-d	Vitamin D	2022-11-14	34	ng/mL	34 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	3	9	Nov 2022	◐ 34	2
alex	vitamin-d	Vitamin D	2023-06-05	41	ng/mL	41 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	4	9	Jun 2023	● 41	2
alex	vitamin-d	Vitamin D	2024-01-15	38	ng/mL	38 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	5	9	Jan 2024	◐ 38	2
alex	vitamin-d	Vitamin D	2024-08-12	47	ng/mL	47 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	6	9	Aug 2024	● 47	2
alex	vitamin-d	Vitamin D	2025-03-10	52	ng/mL	52 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	7	9	Mar 2025	● 52	2
alex	vitamin-d	Vitamin D	2025-09-15	55	ng/mL	55 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	8	9	Sep 2025	● 55	2
alex	tsh	TSH	2021-11-08	1.8	mIU/L	1.8 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	1	10	Nov 2021	● 1.8	0
alex	tsh	TSH	2022-05-16	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	2	10	May 2022	● 2.1	0
alex	tsh	TSH	2022-11-14	1.9	mIU/L	1.9 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	3	10	Nov 2022	● 1.9	0
alex	tsh	TSH	2023-06-05	2.4	mIU/L	2.4 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	4	10	Jun 2023	● 2.4	0
alex	tsh	TSH	2024-01-15	2.2	mIU/L	2.2 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	5	10	Jan 2024	● 2.2	0
alex	tsh	TSH	2024-08-12	2.0	mIU/L	2 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	6	10	Aug 2024	● 2	0
alex	tsh	TSH	2025-03-10	2.3	mIU/L	2.3 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	7	10	Mar 2025	● 2.3	0
alex	tsh	TSH	2025-09-15	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	8	10	Sep 2025	● 2.1	0
alex	ferritin	Ferritin	2021-11-08	182	ng/mL	182 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	1	11	Nov 2021	◐ 182	0
alex	ferritin	Ferritin	2022-05-16	195	ng/mL	195 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	2	11	May 2022	◐ 195	0
alex	ferritin	Ferritin	2022-11-14	210	ng/mL	210 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	3	11	Nov 2022	◐ 210	0
alex	ferritin	Ferritin	2023-06-05	188	ng/mL	188 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	4	11	Jun 2023	◐ 188	0
alex	ferritin	Ferritin	2024-01-15	176	ng/mL	176 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	5	11	Jan 2024	◐ 176	0
alex	ferritin	Ferritin	2024-08-12	169	ng/mL	169 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	6	11	Aug 2024	◐ 169	0
alex	ferritin	Ferritin	2025-03-10	160	ng/mL	160 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	7	11	Mar 2025	◐ 160	0
alex	ferritin	Ferritin	2025-09-15	154	ng/mL	154 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	8	11	Sep 2025	◐ 154	0
alex	testosterone-total	Testosterone	2021-11-08	412	ng/dL	412 ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	264	916	500	900	1	12	Nov 2021	◐ 412	0
alex	testosterone-total	Testosterone	2022-05-16	438	ng/dL	438 ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	264	916	500	900	2	12	May 2022	◐ 438	0
alex	testosterone-total	Testosterone	2022-11-14	465	ng/dL	465 ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	264	916	500	900	3	12	Nov 2022	◐ 465	0
alex	testosterone-total	Testosterone	2023-06-05	512	ng/dL	512 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	4	12	Jun 2023	● 512	0
alex	testosterone-total	Testosterone	2024-01-15	548	ng/dL	548 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	5	12	Jan 2024	● 548	0
alex	testosterone-total	Testosterone	2024-08-12	575	ng/dL	575 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	6	12	Aug 2024	● 575	0
alex	testosterone-total	Testosterone	2025-03-10	602	ng/dL	602 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	7	12	Mar 2025	● 602	0
alex	testosterone-total	Testosterone	2025-09-15	618	ng/dL	618 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	8	12	Sep 2025	● 618	0
alex	alt	ALT	2021-11-08	48	U/L	48 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	1	13	Nov 2021	◐ 48	1
alex	alt	ALT	2022-05-16	52	U/L	52 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	2	13	May 2022	◐ 52	1
alex	alt	ALT	2022-11-14	61	U/L	61 U/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	7	56	NaN	30	3	13	Nov 2022	▲ 61	1
alex	alt	ALT	2023-06-05	44	U/L	44 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	4	13	Jun 2023	◐ 44	1
alex	alt	ALT	2024-01-15	36	U/L	36 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	5	13	Jan 2024	◐ 36	1
alex	alt	ALT	2024-08-12	29	U/L	29 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	6	13	Aug 2024	● 29	1
alex	alt	ALT	2025-03-10	26	U/L	26 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	7	13	Mar 2025	● 26	1
alex	alt	ALT	2025-09-15	24	U/L	24 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	8	13	Sep 2025	● 24	1
EOD

array YL = ['LDL-C', 'HDL-C', 'Triglycerides', 'ApoB', 'Lp(a)', 'HbA1c', 'Glucose', 'hs-CRP', 'Vitamin D', 'TSH', 'Ferritin', 'Testosterone', 'ALT']
array XL = ['Nov 2021', 'May 2022', 'Nov 2022', 'Jun 2023', 'Jan 2024', 'Aug 2024', 'Mar 2025', 'Sep 2025']
array LK = ['optimal', 'suboptimal', 'low', 'high']
array LL = ['● optimal', '◐ suboptimal', '▼ low', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b', '#d03b3b']
ny = |YL|
nx = |XL|
text = ('svg' eq 'text')
w = 0.46
h = 0.44

set label 1 'Status by draw · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 '13 markers × 8 draws; 32 out of range' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 6.5
set lmargin 17
set rmargin 3
set bmargin 3.5
set border 0
set xrange [0.5:nx+0.5]
set yrange [ny+0.5:0.5]
set x2range [0.5:nx+0.5]
unset xtics
set x2tics scale 0 nomirror textcolor rgb '#52514e' font ',10.5' offset 0,-0.3
set x2tics ()
do for [i=1:nx] { set x2tics add (XL[i] i) }
set ytics scale 0 nomirror textcolor rgb '#0b0b0b' offset -0.5,0
set ytics ()
do for [i=1:ny] { set ytics add (YL[i] i) }
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' \
    samplen 1.5 spacing 1.2 width 2

if (text) {
  # Dumb terminal: no fills; the glyph and value are the cell.
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  th = 20
  if (th < ny + 6) { th = ny + 6; set terminal dumb noenhanced size 72, th }
  set tmargin th - ny - 2; set lmargin 22; set rmargin 1; set bmargin 2
  key = ''
  do for [i=1:|LL|] { key = key . LL[i] . '   ' }
  set label 3 key at graph 0, screen 0 offset 0,0.5 left
  unset ytics; unset x2tics; unset key
  do for [i=1:nx] { set label 200+i XL[i][1:3] . "\n" . XL[i][5:] at first i, graph 1 offset 0,2.5 center }
  do for [i=1:ny] { set label 100+i YL[i] at graph 0, first i offset -1,0 right }
  plot $data using 'x_index':'y_index':'cell_label' with labels
} else {
  # The grid, then the key alone in a full-width plot below it so its
  # entries spread across the figure in one row.
  set multiplot
  unset key
  plot \
    for [i=1:|LK|] $data using 'x_index':(strcol('status') eq LK[i] ? column('y_index') : NaN) \
        :(column('x_index')-w):(column('x_index')+w):(column('y_index')-h):(column('y_index')+h) \
        with boxxyerror fillcolor rgb LC[i] fillstyle solid 0.9 noborder, \
    $data using 'x_index':'y_index':'cell_label' with labels font ',11.5' textcolor rgb '#fcfcfb'
  unset label; unset ytics; unset x2tics
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.07; set bmargin at screen 0.005
  set yrange [0:1]
  set key inside center center horizontal Left reverse noautotitle textcolor rgb '#52514e' \
      samplen 1.5 spacing 1.2 width 2
  plot 2 with lines linecolor rgb '#fcfcfb' notitle, \
    for [i=1:|LK|] keyentry with boxes fillcolor rgb LC[i] fillstyle solid 0.9 noborder title LL[i]
  unset multiplot
}
