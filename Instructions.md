# Instructions

Hello, and thanks for taking the time to interview with us at Tracksuit! This is a take-home exercise we'd like you to complete. This is an open-ended problem that is designed to showcase your thoughtfulness and creativity. To avoid spending too much time on this task, we encourage you to timebox your work to a few hours.

<!-- deno-fmt-ignore-start -->
> [!Note]
> This task is meant to give us something to talk over in your technical
> interview. It is a challenging but realistic example of the kind of
> problems you may tackle at Tracksuit and you're encouraged to use AI
> to assist you. Finally, remember: Nothing is designed to trick you.
> If you have any questions, please reach out! 
<!-- deno-fmt-ignore-end -->

## Background

Share of Search is an increasingly popular marketing metric. Studies have shown that it is an accurate proxy for market share, can predict future market growth, and - most importantly - is easier and cheaper to collect than Share of Voice and brand tracking.

Tracksuit sees this as a potential opportunity: Beyond the immediate demand for Share of Search from our clients, we suspect search data may address some of the challenges around the cost, reliability, and limited capacity of traditional survey panels.

In this task, imagine you’re a Data Scientist at Tracksuit tasked to explore the product and business potential of search for Tracksuit.

## The Task

Your task is to design, conduct, and present a basic study that explores the relationship between search (and share of search) and a sample of our brand metrics. Your study should lead to a recommendation of whether and how Tracksuit can use search data to complement or substitute survey data in this space, to accomplish our vision of being the common language to measure, understand and communicate the value of brand.

This task seeks to understand your product and market research thinking, alongside your statistical, programming, and communication skills. We want to understand how you reason and communicate technically and statistically and balance sophistication with a sensitivity for a less technical end user. To be clear, while we want to see some analysis and implementation to understand your statistical and programming abilities, we expect you to make trade-offs - this should be a limited study with significant caveats.

Since we'll be reviewing your work asynchronously, please follow the instructions in the [README](./README.md) to submit your task. You're welcome to use your programming language and framework of choice but please ensure your full solution is reproducible from your code. 

You're also more than welcome to use any AI tools (e.g. Cursor or Claude Code) to help you with this take home task, similarly to how you would as an employee at Tracksuit. However, similarly to any code you write at Tracksuit, you will be responsible for the quality of your code and your results. Make sure you can interpret and explain any code, assumptions, and results that you submit. Please note that we will be comparing your results to a naive Claude Code solution based on this repository. You'll need to contribute additional insight or intuition to achieve a strong performance. 

Validation is a critical part of all work that we do at Tracksuit. Please make sure to document your work to help us understand the robustness of any analysis you conduct.

### The Sample Data

Tracksuit's bread-and-butter is brand health tracking. This involves deploying monthly syndicated surveys that ask respondents about their general purchase behavior (category qualifier) and their attitudinal preferences on a representative set of brands within each category.

At its most basic, these attitudinal preferences can be represented by a set of three basic funnel questions: Prompted awareness, consideration, and preference. Prompted awareness asks whether respondents have heard of a brand, given its name and logo. Consideration asks which brands respondents have considered purchasing. Finally, preference asks respondents for their preferred brand. These are considered "funnel" questions since we assume that a respondent cannot consider a brand they're not aware of, and that they would not prefer a brand they have not considered.

Broadly, this data allows Tracksuit clients to assess:
- The size of the market (category penetration, or the percentage of the population that purchases the given category)
- Their awareness (the proportion of the category that is aware of their brand when prompted), relative to their competitors
- The size and composition of consumer's consideration sets, including each brand's rate of conversion from awareness to consideration
- Where they have the most brand affinity (preference)
Understanding these points gives brands a sense of where they sit in the market, relative to their competitor set, and what their brand marketing goals should be.

For the purposes of this task, search is often used as a proxy metric for consideration - both imply some consumer intent (one claimed, one behavioral). 

We provide a set of 50 Australian categories, along with their associated brands and awareness, consideration, and preference metrics, in the spreadsheet `sample_category_data.csv`. This is not a comprehensive view of all the data Tracksuit collects but it should provide a starting point for your analysis. 

This data is collected from a representative sample of the Australian population (18 years old+) on a monthly basis. We aim to collect a sample of 200 qualified respondents per category (200 respondents who purchase in the category) per month.

Here is the associated data dictionary:

**_Data dictionary_**
- category_name: the name for the category
- geography_name: the name of the country the survey was conducted in (Australia)
- brand_name: the brand associated with the given funnel metric
- wave_date: the month the survey data was collected
- std_question: the brand health metric in question; one of `PROMPTED_AWARENESS`, `CONSIDERATION`, and `PREFERENCE`
- weight_1: the weight of respondents who responded positively to the question; this should be close to the number of people who responded positively to the question
- base_weight_1: the weight of respondents who were asked the question (i.e. qualified for the category)
- percentage_1: the value of the metric, calculated by `weight_1 / base_weight_1`
