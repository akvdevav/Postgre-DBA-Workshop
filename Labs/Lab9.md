### Lab: Managing ML Risk & Governance in a Financial Database

Objective:
Equip financial DBAs with the skills to secure ML extensions, enforce strict Role-Based Access Control (RBAC) between Quants and Applications, and audit predictive models (like Loan Default risk) stored directly in the PostgreSQL instance.

#### Step 1: Initialize & Generate Synthetic Financial Data
Launch the container using your Podman command, then connect to psql. We will enable the extension and build a 1,000-row synthetic dataset representing historical loan applications.

```
podman run \
    -it \
    -v postgresml_data:/var/lib/postgresql \
    -p 5433:5432 \
    -p 8000:8000 \
    ghcr.io/postgresml/postgresml:2.10.0 \
    sudo -u postgresml psql -d postgresml
```

```
CREATE DATABASE finance;
```

```
\c finance
```

```
-- 1. Enable the PostgresML extension
CREATE EXTENSION IF NOT EXISTS pgml;
```

```
-- 2. Generate synthetic loan history data
CREATE TABLE public.loan_history AS
SELECT 
    id AS loan_id,
    (random() * 300 + 500)::integer AS credit_score,
    (random() * 0.5 + 0.1)::real AS dti_ratio, -- Debt-to-Income
    (random() * 90000 + 10000)::real AS loan_amount,
    0 AS defaulted
FROM generate_series(1, 1000) AS id;
```

```
-- 3. Create a logical pattern for the ML model to learn 
-- (High DTI or low credit score results in a default)
UPDATE public.loan_history 
SET defaulted = 1 
WHERE credit_score < 650 OR dti_ratio > 0.40;
```

```
-- 4. Verify the data
SELECT * FROM public.loan_history LIMIT 5;
```


#### Step 2: Enforce Separation of Duties (RBAC)
In a bank, the Quantitative Analyst (Quant) who builds the model is never the same identity as the Banking API that executes it. We will strictly separate these roles to prevent unauthorized compute usage.

```
-- 1. Create distinct roles
CREATE ROLE quant_admin WITH LOGIN PASSWORD 'quant_pw';
CREATE ROLE banking_app WITH LOGIN PASSWORD 'app_pw';
```

```
-- 2. Grant basic schema and data access
GRANT USAGE ON SCHEMA pgml TO quant_admin, banking_app;
GRANT SELECT ON public.loan_history TO quant_admin, banking_app;
```

```
-- 3. Lock down training functions from the public!
REVOKE EXECUTE ON FUNCTION pgml.train FROM PUBLIC;
```

```
-- 4. Quant Permissions: Write access to metadata and permission to train
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA pgml TO quant_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA pgml TO quant_admin;
GRANT EXECUTE ON FUNCTION pgml.train TO quant_admin;
```

```
-- 5. Application Permissions: Read-only metadata and specific execution
GRANT SELECT ON ALL TABLES IN SCHEMA pgml TO banking_app;
```

```
-- *CRITICAL DBA GOTCHA*: We must specify the exact argument types 
-- because pgml.predict is an overloaded function!
GRANT EXECUTE ON FUNCTION pgml.predict(text, real[]) TO banking_app;
GRANT EXECUTE ON FUNCTION pgml.predict(text, double precision[]) TO banking_app;
```

```
-- 1. Create a clean training view without the loan_id
CREATE VIEW public.loan_training_data AS
SELECT credit_score, dti_ratio, loan_amount, defaulted
FROM public.loan_history;
```

```
GRANT SELECT ON public.loan_training_data TO quant_admin, banking_app;
```

#### Step 3: Train the Risk Model (Quant Simulation)
Switch context to simulate the Quant deploying a risk model. We will train a classification model to predict whether a loan will default based on historical data.

```
-- Switch to the Quant role
SET ROLE quant_admin;
```

```
-- Train a classification model named 'Loan Default Predictor'
SELECT * FROM pgml.train(
    project_name => 'Loan Default Predictor',
    task => 'classification',
    relation_name => 'public.loan_training_data', -- Updated to use the view
    y_column_name => 'defaulted',
    algorithm => 'xgboost'
);
```

#### Step 4: Compliance & Audit (DBA Simulation)
Switch back to the superuser. In a financial audit, DBAs need to prove exactly what models exist in the database, what algorithms they use, and when they were deployed.

```
-- Revert back to superuser (DBA)
RESET ROLE;
```

```
-- 1. View all ML projects (e.g., Fraud, Loan Risk, Churn)
SELECT id, name, task FROM pgml.projects;
```

```
-- 2. Audit the trained models to see the algorithm and accuracy (F1 score)
SELECT 
    project_id, 
    algorithm, 
    runtime, 
    metrics->>'f1' AS f1_accuracy_score
FROM pgml.models;
```

```
-- 3. Check which specific model version is currently live in production
SELECT project_id, model_id, strategy FROM pgml.deployments;
```

#### Step 5: Test Real-Time Inference (Application Simulation)
Finally, switch to the banking_app role. We will test a real-time prediction simulating a new loan application hitting the database.

```
-- Switch to the Banking Application role
SET ROLE banking_app;
```

```
-- 1. Prove the app CANNOT train a model (Compliance check: Permission Denied)
SELECT * FROM pgml.train('Rogue Model', 'classification', 'public.loan_history', 'defaulted');
```

```
-- 2. Score a new loan application in real-time!
-- We pass an array of features: [credit_score, dti_ratio, loan_amount]
SELECT 
    pgml.predict(
        'Loan Default Predictor', 
        ARRAY[610, 0.45, 25000]::real[]
    ) AS predicted_default_risk; 
    -- Expected output: 1 (High Risk / Default)
```


```
-- 3. Score a new loan application in real-time!
-- We pass an array of features: [credit_score, dti_ratio, loan_amount]
SELECT 
    pgml.predict(
        'Loan Default Predictor', 
        ARRAY[780, 0.15, 50000]::real[]
    ) AS predicted_default_risk; 
    -- Expected output: 0 (Low Risk / Safe)
```


```
SELECT current_user, session_user;
```