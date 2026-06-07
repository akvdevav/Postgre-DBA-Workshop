### Lab: Managing In-Database Machine Learning with PostgresML

#### Objective:
Equip DBAs with the skills to secure machine learning extensions, enforce Role-Based Access Control (RBAC) for model training vs. execution, and audit the ML models stored inside their PostgreSQL instances.

#### Step 1: Launch the Environment & Initialize
First, we will use Docker Desktop to spin up the PostgresML container and jump straight into an interactive psql session as the superuser.

```
docker run \
    -it \
    -v postgresml_data:/var/lib/postgresql \
    -p 5433:5432 \
    -p 8000:8000 \
    ghcr.io/postgresml/postgresml:2.10.0 \
    sudo -u postgresml psql -d postgresml
```
Once inside psql, initialize the extension and load a sample dataset (the standard Sklearn Diabetes dataset) so we have something to work with.

```
-- 1. Enable the PostgresML extension
CREATE EXTENSION IF NOT EXISTS pgml;
```

```
-- 2. Load the sample dataset (creates the table pgml.diabetes)
SELECT pgml.load_dataset('diabetes');
```

```
-- 3. Verify the data is present
SELECT * FROM pgml.diabetes LIMIT 5;
```

#### Step 2: Implement RBAC (The DBA Superpower)
By default, Postgres often grants EXECUTE on functions to PUBLIC. Model training is highly CPU-intensive. As a DBA, the first rule of in-database ML is never let standard application users train models.

We will create two distinct roles: ml_admin (Data Scientist) and app_user (Application/API).

```
-- 1. Create our two distinct users
CREATE ROLE ml_admin WITH LOGIN PASSWORD 'ml_admin_pw';
CREATE ROLE app_user WITH LOGIN PASSWORD 'app_user_pw';
```

```
-- 2. Grant basic schema access
GRANT USAGE ON SCHEMA pgml TO ml_admin, app_user;
GRANT SELECT ON pgml.diabetes TO ml_admin, app_user;
```

```
-- 3. Lock down the heavy-lifting functions! 
-- Prevent the public from training models or loading datasets
REVOKE EXECUTE ON FUNCTION pgml.train FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pgml.load_dataset FROM PUBLIC;
```

```
-- 4. Give the Data Scientist (ml_admin) permissions to train models
-- They need write access to pgml metadata tables to save the models
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA pgml TO ml_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA pgml TO ml_admin;
GRANT EXECUTE ON FUNCTION pgml.train TO ml_admin;
```

```
-- 5. Give the App User (app_user) ONLY permission to run predictions
-- They only need to read the model metadata
GRANT SELECT ON ALL TABLES IN SCHEMA pgml TO app_user;
GRANT EXECUTE ON FUNCTION pgml.predict TO app_user;
```

```
-- Grant access to the specific overloaded versions of pgml.predict
GRANT EXECUTE ON FUNCTION pgml.predict(text, real[]) TO app_user;
GRANT EXECUTE ON FUNCTION pgml.predict(text, double precision[]) TO app_user;
```

```
-- (Optional) If you plan to do NLP or text classification labs later:
-- GRANT EXECUTE ON FUNCTION pgml.predict(text, text) TO app_user;
```

#### Step 3: Train the Model (Data Scientist Simulation)
Now, switch context to simulate a Data Scientist deploying a model. We will train a simple regression model to predict diabetes progression.

```
-- Switch to the Data Scientist role
SET ROLE ml_admin;
```

```
-- Train a model named 'Diabetes Regression Model'
-- PostgresML will automatically handle the algorithm, testing, and deployment
SELECT * FROM pgml.train(
    project_name => 'Diabetes Regression Model',
    task => 'regression',
    relation_name => 'pgml.diabetes',
    y_column_name => 'target',
    algorithm => 'linear'
);

```

#### Step 4: Audit & Manage Models (DBA Simulation)
Switch back to the superuser (DBA). One of the biggest challenges for DBAs with ML is knowing what is eating up storage and compute. PostgresML stores all model metadata, metrics, and serialized binaries directly in standard Postgres tables.

```
-- Revert back to superuser
RESET ROLE;
```

```
-- 1. View all ML projects in the database
SELECT id, name, task FROM pgml.projects;
```

```
-- 2. View the actual trained models, their algorithms, and their metrics
-- DBAs can use this to monitor when models were created and how large they are
SELECT 
    project_id, 
    algorithm, 
    runtime, 
    metrics->>'r2' AS r_squared_accuracy
FROM pgml.models;
```

```
-- 3. Check active deployments 
-- (PostgresML automatically deploys the best-performing model to production)
SELECT project_id, model_id, strategy FROM pgml.deployments;
```

#### Step 5: Test Inference (Application Simulation)
Finally, let's prove our RBAC works. Switch to the app_user role. This user should be able to run predictions (pgml.predict) on real-time data but will be blocked if they attempt to trigger a training job.

```
-- Switch to the Application user
SET ROLE app_user;
```

```
-- 1. Verify the app user CANNOT train a model (This should throw a Permission Denied error)
SELECT * FROM pgml.train('Test', 'regression', 'pgml.diabetes', 'target');
```

```
-- 2. Run a prediction on the live data!
-- We pass the model name and an ARRAY of the exact features it was trained on
SELECT 
    target AS actual_progression, 
    ROUND(
        pgml.predict(
            'Diabetes Regression Model', 
            ARRAY[age, sex, bmi, bp, s1, s2, s3, s4, s5, s6]
        )::numeric, 2
    ) AS predicted_progression
FROM pgml.diabetes
LIMIT 5;
```

```
RESET ROLE;
```

#### Notes for DBAs:
It feels native: It uses standard PostgreSQL DCL (GRANT/REVOKE) to solve an MLOps problem, translating a foreign concept into their native language.

It highlights observability: Querying the pgml.models table shows DBAs exactly where the "black box" algorithms live.

It addresses fear: Proving that a DBA can prevent an application bug from kicking off a 100% CPU training loop provides immense peace of mind.

