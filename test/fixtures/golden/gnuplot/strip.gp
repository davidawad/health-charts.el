# health-chart: strip chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,582 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart strip: every draw of every marker on its own range scale
# (0 = reference low, 1 = reference high); earlier draws as grey ticks,
# the latest as a status shape with its glyph and word in the label.
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	index	draws	norm	x	clipped	latest	ref_x	ref_x2	opt_x	opt_x2	ref_range	opt_range	latest_label
alex	ldl-c	LDL-C	2021-11-08	162	mg/dL	162 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	1	8	1.62	1.62	0	0	0	1	-0.25	0.7	0–100	≤70	162 mg/dL  ▲ high
alex	ldl-c	LDL-C	2022-05-16	151	mg/dL	151 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	1	8	1.51	1.51	0	0	0	1	-0.25	0.7	0–100	≤70	151 mg/dL  ▲ high
alex	ldl-c	LDL-C	2022-11-14	138	mg/dL	138 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	1	8	1.38	1.38	0	0	0	1	-0.25	0.7	0–100	≤70	138 mg/dL  ▲ high
alex	ldl-c	LDL-C	2023-06-05	121	mg/dL	121 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	1	8	1.21	1.21	0	0	0	1	-0.25	0.7	0–100	≤70	121 mg/dL  ▲ high
alex	ldl-c	LDL-C	2024-01-15	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	1	8	1.04	1.04	0	0	0	1	-0.25	0.7	0–100	≤70	104 mg/dL  ▲ high
alex	ldl-c	LDL-C	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	1	8	0.92	0.92	0	0	0	1	-0.25	0.7	0–100	≤70	92 mg/dL  ◐ suboptimal
alex	ldl-c	LDL-C	2025-03-10	84	mg/dL	84 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	1	8	0.84	0.84	0	0	0	1	-0.25	0.7	0–100	≤70	84 mg/dL  ◐ suboptimal
alex	ldl-c	LDL-C	2025-09-15	76	mg/dL	76 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	1	8	0.76	0.76	0	1	0	1	-0.25	0.7	0–100	≤70	76 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2021-11-08	38	mg/dL	38 mg/dL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	40	NaN	60	NaN	2	8	-0.05	-0.05	0	0	0	1	0.5	2.25	≥40	≥60	38 mg/dL  ▼ low
alex	hdl-c	HDL-C	2022-05-16	41	mg/dL	41 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	8	0.025	0.025	0	0	0	1	0.5	2.25	≥40	≥60	41 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2022-11-14	44	mg/dL	44 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	8	0.1	0.1	0	0	0	1	0.5	2.25	≥40	≥60	44 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2023-06-05	47	mg/dL	47 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	8	0.175	0.175	0	0	0	1	0.5	2.25	≥40	≥60	47 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2024-01-15	52	mg/dL	52 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	8	0.3	0.3	0	0	0	1	0.5	2.25	≥40	≥60	52 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2024-08-12	55	mg/dL	55 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	8	0.375	0.375	0	0	0	1	0.5	2.25	≥40	≥60	55 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2025-03-10	58	mg/dL	58 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	2	8	0.45	0.45	0	0	0	1	0.5	2.25	≥40	≥60	58 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2025-09-15	61	mg/dL	61 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	40	NaN	60	NaN	2	8	0.525	0.525	0	1	0	1	0.5	2.25	≥40	≥60	61 mg/dL  ● optimal
alex	triglycerides	Triglycerides	2021-11-08	212	mg/dL	212 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	150	NaN	100	3	8	1.4133	1.4133	0	0	0	1	-0.25	0.6667	0–150	≤100	212 mg/dL  ▲ high
alex	triglycerides	Triglycerides	2022-05-16	188	mg/dL	188 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	150	NaN	100	3	8	1.2533	1.2533	0	0	0	1	-0.25	0.6667	0–150	≤100	188 mg/dL  ▲ high
alex	triglycerides	Triglycerides	2022-11-14	160	mg/dL	160 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	150	NaN	100	3	8	1.0667	1.0667	0	0	0	1	-0.25	0.6667	0–150	≤100	160 mg/dL  ▲ high
alex	triglycerides	Triglycerides	2023-06-05	138	mg/dL	138 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	150	NaN	100	3	8	0.92	0.92	0	0	0	1	-0.25	0.6667	0–150	≤100	138 mg/dL  ◐ suboptimal
alex	triglycerides	Triglycerides	2024-01-15	121	mg/dL	121 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	150	NaN	100	3	8	0.8067	0.8067	0	0	0	1	-0.25	0.6667	0–150	≤100	121 mg/dL  ◐ suboptimal
alex	triglycerides	Triglycerides	2024-08-12	104	mg/dL	104 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	150	NaN	100	3	8	0.6933	0.6933	0	0	0	1	-0.25	0.6667	0–150	≤100	104 mg/dL  ◐ suboptimal
alex	triglycerides	Triglycerides	2025-03-10	96	mg/dL	96 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	150	NaN	100	3	8	0.64	0.64	0	0	0	1	-0.25	0.6667	0–150	≤100	96 mg/dL  ● optimal
alex	triglycerides	Triglycerides	2025-09-15	88	mg/dL	88 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	150	NaN	100	3	8	0.5867	0.5867	0	1	0	1	-0.25	0.6667	0–150	≤100	88 mg/dL  ● optimal
alex	apob	ApoB	2021-11-08	128	mg/dL	128 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	4	8	1.4222	1.4222	0	0	0	1	-0.25	0.8889	0–90	≤80	128 mg/dL  ▲ high
alex	apob	ApoB	2022-05-16	120	mg/dL	120 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	4	8	1.3333	1.3333	0	0	0	1	-0.25	0.8889	0–90	≤80	120 mg/dL  ▲ high
alex	apob	ApoB	2022-11-14	111	mg/dL	111 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	4	8	1.2333	1.2333	0	0	0	1	-0.25	0.8889	0–90	≤80	111 mg/dL  ▲ high
alex	apob	ApoB	2023-06-05	98	mg/dL	98 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	90	NaN	80	4	8	1.0889	1.0889	0	0	0	1	-0.25	0.8889	0–90	≤80	98 mg/dL  ▲ high
alex	apob	ApoB	2024-01-15	88	mg/dL	88 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	90	NaN	80	4	8	0.9778	0.9778	0	0	0	1	-0.25	0.8889	0–90	≤80	88 mg/dL  ◐ suboptimal
alex	apob	ApoB	2024-08-12	81	mg/dL	81 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	90	NaN	80	4	8	0.9	0.9	0	0	0	1	-0.25	0.8889	0–90	≤80	81 mg/dL  ◐ suboptimal
alex	apob	ApoB	2025-03-10	76	mg/dL	76 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	90	NaN	80	4	8	0.8444	0.8444	0	0	0	1	-0.25	0.8889	0–90	≤80	76 mg/dL  ● optimal
alex	apob	ApoB	2025-09-15	72	mg/dL	72 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	90	NaN	80	4	8	0.8	0.8	0	1	0	1	-0.25	0.8889	0–90	≤80	72 mg/dL  ● optimal
alex	lpa	Lp(a)	2021-11-08	142	nmol/L	142 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.8933	1.8933	0	0	0	1	-0.25	0.4	0–75	≤30	142 nmol/L  ▲ high
alex	lpa	Lp(a)	2022-05-16	148	nmol/L	148 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.9733	1.9733	0	0	0	1	-0.25	0.4	0–75	≤30	148 nmol/L  ▲ high
alex	lpa	Lp(a)	2022-11-14	139	nmol/L	139 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.8533	1.8533	0	0	0	1	-0.25	0.4	0–75	≤30	139 nmol/L  ▲ high
alex	lpa	Lp(a)	2023-06-05	151	nmol/L	151 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	2.0133	2.0133	0	0	0	1	-0.25	0.4	0–75	≤30	151 nmol/L  ▲ high
alex	lpa	Lp(a)	2024-01-15	145	nmol/L	145 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.9333	1.9333	0	0	0	1	-0.25	0.4	0–75	≤30	145 nmol/L  ▲ high
alex	lpa	Lp(a)	2024-08-12	140	nmol/L	140 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.8667	1.8667	0	0	0	1	-0.25	0.4	0–75	≤30	140 nmol/L  ▲ high
alex	lpa	Lp(a)	2025-03-10	149	nmol/L	149 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.9867	1.9867	0	0	0	1	-0.25	0.4	0–75	≤30	149 nmol/L  ▲ high
alex	lpa	Lp(a)	2025-09-15	144	nmol/L	144 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	8	1.92	1.92	0	1	0	1	-0.25	0.4	0–75	≤30	144 nmol/L  ▲ high
alex	hba1c	HbA1c	2021-11-08	5.9	%	5.9 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	6	8	1.1875	1.1875	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.9 %  ▲ high
alex	hba1c	HbA1c	2022-05-16	5.8	%	5.8 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	6	8	1.125	1.125	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.8 %  ▲ high
alex	hba1c	HbA1c	2022-11-14	5.7	%	5.7 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	6	8	1.0625	1.0625	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.7 %  ▲ high
alex	hba1c	HbA1c	2023-06-05	5.6	%	5.6 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	6	8	1	1	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.6 %  ◐ suboptimal
alex	hba1c	HbA1c	2024-01-15	5.5	%	5.5 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	6	8	0.9375	0.9375	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.5 %  ◐ suboptimal
alex	hba1c	HbA1c	2024-08-12	5.4	%	5.4 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	6	8	0.875	0.875	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.4 %  ◐ suboptimal
alex	hba1c	HbA1c	2025-03-10	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	6	8	0.8125	0.8125	0	0	0	1	-0.25	0.8125	4–5.6	≤5.3	5.3 %  ● optimal
alex	hba1c	HbA1c	2025-09-15	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	6	8	0.8125	0.8125	0	1	0	1	-0.25	0.8125	4–5.6	≤5.3	5.3 %  ● optimal
alex	glucose	Glucose	2021-11-08	108	mg/dL	108 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	7	8	1.3103	1.3103	0	0	0	1	0.069	0.6897	70–99	72–90	108 mg/dL  ▲ high
alex	glucose	Glucose	2022-05-16	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	7	8	1.1724	1.1724	0	0	0	1	0.069	0.6897	70–99	72–90	104 mg/dL  ▲ high
alex	glucose	Glucose	2022-11-14	101	mg/dL	101 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	7	8	1.069	1.069	0	0	0	1	0.069	0.6897	70–99	72–90	101 mg/dL  ▲ high
alex	glucose	Glucose	2023-06-05	97	mg/dL	97 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	7	8	0.931	0.931	0	0	0	1	0.069	0.6897	70–99	72–90	97 mg/dL  ◐ suboptimal
alex	glucose	Glucose	2024-01-15	94	mg/dL	94 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	7	8	0.8276	0.8276	0	0	0	1	0.069	0.6897	70–99	72–90	94 mg/dL  ◐ suboptimal
alex	glucose	Glucose	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	7	8	0.7586	0.7586	0	0	0	1	0.069	0.6897	70–99	72–90	92 mg/dL  ◐ suboptimal
alex	glucose	Glucose	2025-03-10	96	mg/dL	96 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	7	8	0.8966	0.8966	0	0	0	1	0.069	0.6897	70–99	72–90	96 mg/dL  ◐ suboptimal
alex	glucose	Glucose	2025-09-15	89	mg/dL	89 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	70	99	72	90	7	8	0.6552	0.6552	0	1	0	1	0.069	0.6897	70–99	72–90	89 mg/dL  ● optimal
alex	hscrp	hs-CRP	2021-11-08	4.2	mg/L	4.2 mg/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	3.0	NaN	1.0	8	8	1.4	1.4	0	0	0	1	-0.25	0.3333	0–3	≤1	4.2 mg/L  ▲ high
alex	hscrp	hs-CRP	2022-05-16	3.6	mg/L	3.6 mg/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	3.0	NaN	1.0	8	8	1.2	1.2	0	0	0	1	-0.25	0.3333	0–3	≤1	3.6 mg/L  ▲ high
alex	hscrp	hs-CRP	2022-11-14	2.8	mg/L	2.8 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	8	8	0.9333	0.9333	0	0	0	1	-0.25	0.3333	0–3	≤1	2.8 mg/L  ◐ suboptimal
alex	hscrp	hs-CRP	2023-06-05	2.1	mg/L	2.1 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	8	8	0.7	0.7	0	0	0	1	-0.25	0.3333	0–3	≤1	2.1 mg/L  ◐ suboptimal
alex	hscrp	hs-CRP	2024-01-15	1.6	mg/L	1.6 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	8	8	0.5333	0.5333	0	0	0	1	-0.25	0.3333	0–3	≤1	1.6 mg/L  ◐ suboptimal
alex	hscrp	hs-CRP	2024-08-12	1.2	mg/L	1.2 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	8	8	0.4	0.4	0	0	0	1	-0.25	0.3333	0–3	≤1	1.2 mg/L  ◐ suboptimal
alex	hscrp	hs-CRP	2025-03-10	0.9	mg/L	0.9 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	8	8	0.3	0.3	0	0	0	1	-0.25	0.3333	0–3	≤1	0.9 mg/L  ● optimal
alex	hscrp	hs-CRP	2025-09-15	0.8	mg/L	0.8 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	8	8	0.2667	0.2667	0	1	0	1	-0.25	0.3333	0–3	≤1	0.8 mg/L  ● optimal
alex	vitamin-d	Vitamin D	2021-11-08	22	ng/mL	22 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	9	8	-0.1143	-0.1143	0	0	0	1	0.1429	0.4286	30–100	40–60	22 ng/mL  ▼ low
alex	vitamin-d	Vitamin D	2022-05-16	26	ng/mL	26 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	9	8	-0.0571	-0.0571	0	0	0	1	0.1429	0.4286	30–100	40–60	26 ng/mL  ▼ low
alex	vitamin-d	Vitamin D	2022-11-14	34	ng/mL	34 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	9	8	0.0571	0.0571	0	0	0	1	0.1429	0.4286	30–100	40–60	34 ng/mL  ◐ suboptimal
alex	vitamin-d	Vitamin D	2023-06-05	41	ng/mL	41 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	9	8	0.1571	0.1571	0	0	0	1	0.1429	0.4286	30–100	40–60	41 ng/mL  ● optimal
alex	vitamin-d	Vitamin D	2024-01-15	38	ng/mL	38 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	9	8	0.1143	0.1143	0	0	0	1	0.1429	0.4286	30–100	40–60	38 ng/mL  ◐ suboptimal
alex	vitamin-d	Vitamin D	2024-08-12	47	ng/mL	47 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	9	8	0.2429	0.2429	0	0	0	1	0.1429	0.4286	30–100	40–60	47 ng/mL  ● optimal
alex	vitamin-d	Vitamin D	2025-03-10	52	ng/mL	52 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	9	8	0.3143	0.3143	0	0	0	1	0.1429	0.4286	30–100	40–60	52 ng/mL  ● optimal
alex	vitamin-d	Vitamin D	2025-09-15	55	ng/mL	55 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	9	8	0.3571	0.3571	0	1	0	1	0.1429	0.4286	30–100	40–60	55 ng/mL  ● optimal
alex	tsh	TSH	2021-11-08	1.8	mIU/L	1.8 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.3889	0.3889	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	1.8 mIU/L  ● optimal
alex	tsh	TSH	2022-05-16	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.4722	0.4722	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	2.1 mIU/L  ● optimal
alex	tsh	TSH	2022-11-14	1.9	mIU/L	1.9 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.4167	0.4167	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	1.9 mIU/L  ● optimal
alex	tsh	TSH	2023-06-05	2.4	mIU/L	2.4 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.5556	0.5556	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	2.4 mIU/L  ● optimal
alex	tsh	TSH	2024-01-15	2.2	mIU/L	2.2 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.5	0.5	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	2.2 mIU/L  ● optimal
alex	tsh	TSH	2024-08-12	2.0	mIU/L	2 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.4444	0.4444	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	2 mIU/L  ● optimal
alex	tsh	TSH	2025-03-10	2.3	mIU/L	2.3 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.5278	0.5278	0	0	0	1	0.0278	0.5833	0.4–4	0.5–2.5	2.3 mIU/L  ● optimal
alex	tsh	TSH	2025-09-15	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	8	0.4722	0.4722	0	1	0	1	0.0278	0.5833	0.4–4	0.5–2.5	2.1 mIU/L  ● optimal
alex	ferritin	Ferritin	2021-11-08	182	ng/mL	182 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.4108	0.4108	0	0	0	1	0.0541	0.3243	30–400	50–150	182 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2022-05-16	195	ng/mL	195 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.4459	0.4459	0	0	0	1	0.0541	0.3243	30–400	50–150	195 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2022-11-14	210	ng/mL	210 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.4865	0.4865	0	0	0	1	0.0541	0.3243	30–400	50–150	210 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2023-06-05	188	ng/mL	188 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.427	0.427	0	0	0	1	0.0541	0.3243	30–400	50–150	188 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2024-01-15	176	ng/mL	176 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.3946	0.3946	0	0	0	1	0.0541	0.3243	30–400	50–150	176 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2024-08-12	169	ng/mL	169 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.3757	0.3757	0	0	0	1	0.0541	0.3243	30–400	50–150	169 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2025-03-10	160	ng/mL	160 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.3514	0.3514	0	0	0	1	0.0541	0.3243	30–400	50–150	160 ng/mL  ◐ suboptimal
alex	ferritin	Ferritin	2025-09-15	154	ng/mL	154 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	8	0.3351	0.3351	0	1	0	1	0.0541	0.3243	30–400	50–150	154 ng/mL  ◐ suboptimal
alex	testosterone-total	Testosterone	2021-11-08	412	ng/dL	412 ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	264	916	500	900	12	8	0.227	0.227	0	0	0	1	0.362	0.9755	264–916	500–900	412 ng/dL  ◐ suboptimal
alex	testosterone-total	Testosterone	2022-05-16	438	ng/dL	438 ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	264	916	500	900	12	8	0.2669	0.2669	0	0	0	1	0.362	0.9755	264–916	500–900	438 ng/dL  ◐ suboptimal
alex	testosterone-total	Testosterone	2022-11-14	465	ng/dL	465 ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	264	916	500	900	12	8	0.3083	0.3083	0	0	0	1	0.362	0.9755	264–916	500–900	465 ng/dL  ◐ suboptimal
alex	testosterone-total	Testosterone	2023-06-05	512	ng/dL	512 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	8	0.3804	0.3804	0	0	0	1	0.362	0.9755	264–916	500–900	512 ng/dL  ● optimal
alex	testosterone-total	Testosterone	2024-01-15	548	ng/dL	548 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	8	0.4356	0.4356	0	0	0	1	0.362	0.9755	264–916	500–900	548 ng/dL  ● optimal
alex	testosterone-total	Testosterone	2024-08-12	575	ng/dL	575 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	8	0.477	0.477	0	0	0	1	0.362	0.9755	264–916	500–900	575 ng/dL  ● optimal
alex	testosterone-total	Testosterone	2025-03-10	602	ng/dL	602 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	8	0.5184	0.5184	0	0	0	1	0.362	0.9755	264–916	500–900	602 ng/dL  ● optimal
alex	testosterone-total	Testosterone	2025-09-15	618	ng/dL	618 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	8	0.5429	0.5429	0	1	0	1	0.362	0.9755	264–916	500–900	618 ng/dL  ● optimal
alex	alt	ALT	2021-11-08	48	U/L	48 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	13	8	0.8367	0.8367	0	0	0	1	-0.25	0.4694	7–56	≤30	48 U/L  ◐ suboptimal
alex	alt	ALT	2022-05-16	52	U/L	52 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	13	8	0.9184	0.9184	0	0	0	1	-0.25	0.4694	7–56	≤30	52 U/L  ◐ suboptimal
alex	alt	ALT	2022-11-14	61	U/L	61 U/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	7	56	NaN	30	13	8	1.102	1.102	0	0	0	1	-0.25	0.4694	7–56	≤30	61 U/L  ▲ high
alex	alt	ALT	2023-06-05	44	U/L	44 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	13	8	0.7551	0.7551	0	0	0	1	-0.25	0.4694	7–56	≤30	44 U/L  ◐ suboptimal
alex	alt	ALT	2024-01-15	36	U/L	36 U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	7	56	NaN	30	13	8	0.5918	0.5918	0	0	0	1	-0.25	0.4694	7–56	≤30	36 U/L  ◐ suboptimal
alex	alt	ALT	2024-08-12	29	U/L	29 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	13	8	0.449	0.449	0	0	0	1	-0.25	0.4694	7–56	≤30	29 U/L  ● optimal
alex	alt	ALT	2025-03-10	26	U/L	26 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	13	8	0.3878	0.3878	0	0	0	1	-0.25	0.4694	7–56	≤30	26 U/L  ● optimal
alex	alt	ALT	2025-09-15	24	U/L	24 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	13	8	0.3469	0.3469	0	1	0	1	-0.25	0.4694	7–56	≤30	24 U/L  ● optimal
EOD

array YL = ['LDL-C', 'HDL-C', 'Triglycerides', 'ApoB', 'Lp(a)', 'HbA1c', 'Glucose', 'hs-CRP', 'Vitamin D', 'TSH', 'Ferritin', 'Testosterone', 'ALT']
array LK = ['optimal', 'suboptimal', 'high']
array LL = ['● optimal', '◐ suboptimal', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b']
array LP = [7, 13, 9]
n = |YL|
text = ('svg' eq 'text')
h = 0.31
x1 = 2.25

set label 1 'Every draw vs range · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 '13 markers, each on its own scale; grey ticks: earlier draws; marker: latest draw' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 6
set lmargin 17
set rmargin 27
set border 0
set xrange [-0.25:2.25]
set yrange [n+0.7:0.3]
set xtics scale 0 nomirror textcolor rgb '#52514e' offset 0,-0.3
set xtics ()
set xtics add ('reference low' 0, 'reference high' 1)
set xlabel 'position in reference range' textcolor rgb '#52514e' offset 0,0.3
set ytics scale 0 nomirror textcolor rgb '#0b0b0b' offset -0.5,0
set ytics ()
do for [i=1:n] { set ytics add (YL[i] i) }
set bmargin 9
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.5 spacing 1.2 width 1

if (text) {
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set terminal dumb noenhanced size 72, n + 8
  set tmargin 2; set bmargin 4; set lmargin 17; set rmargin 26
  unset xlabel
  unset key
}

if (!text) {
  # The chart, then the key alone in a full-width plot below it so its
  # entries can spread across the figure.
  set multiplot
  unset key
}
plot \
  $data using (column('latest') == 1 && column('ref_x') == column('ref_x') ? 0.5 : NaN):'index':'ref_x':'ref_x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder, \
  $data using (column('latest') == 1 && column('opt_x') == column('opt_x') ? 0.5 : NaN):'index':'opt_x':'opt_x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder, \
  $data using (column('latest') == 0 ? column('x') : NaN):(column('index')-0.3):(0):(0.6) \
      with vectors nohead linewidth 2 linecolor rgb '#898781', \
  for [i=1:|LK|] $data using (column('latest') == 1 && strcol('status') eq LK[i] ? column('x') : NaN):'index' \
      with points pointtype LP[i] pointsize 1.7 linecolor rgb LC[i], \
  $data using (column('latest') == 1 ? x1 : NaN):'index':'latest_label' \
      with labels left offset 1.5,0 textcolor rgb '#0b0b0b'
if (!text) {
  unset label; unset ytics; unset xtics; unset xlabel
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.1; set bmargin at screen 0.01
  set key inside center center horizontal Left reverse noautotitle textcolor rgb '#52514e' \
      samplen 1.5 spacing 1.2 width 2
  set xrange [0:1]; set yrange [0:1]
  plot \
    2 with lines linecolor rgb '#fcfcfb' notitle, \
    keyentry with boxes fillcolor rgb '#b8b7ad' \
        fillstyle transparent solid 0.28 noborder title 'reference range', \
    keyentry with boxes fillcolor rgb '#0ca30c' \
        fillstyle transparent solid 0.14 noborder title 'optimal range', \
    keyentry with lines linecolor rgb '#898781' linewidth 2 title 'earlier draw', \
    for [i=1:|LK|] keyentry with points pointtype LP[i] pointsize 1.7 linecolor rgb LC[i] title LL[i]
  unset multiplot
}
