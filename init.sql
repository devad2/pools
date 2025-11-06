-- Initialize database with PostgresML extensions
CREATE EXTENSION IF NOT EXISTS pgml;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Configure pg_cron to use our database
ALTER SYSTEM SET cron.database_name = 'poolside';
SELECT pg_reload_conf();

-- Create roles
CREATE ROLE web_anon NOLOGIN;
GRANT USAGE ON SCHEMA public TO web_anon;

-- Create API schema for PostgREST
CREATE SCHEMA IF NOT EXISTS api;
GRANT USAGE ON SCHEMA api TO web_anon;

-- Create base tables
CREATE TABLE IF NOT EXISTS api.messages (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed initial data
INSERT INTO api.messages (content) VALUES ('hello world');

-- RAG data storage
CREATE TABLE IF NOT EXISTS api.rag_documents (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    embedding VECTOR(768),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Model training jobs
CREATE TABLE IF NOT EXISTS api.training_jobs (
    id SERIAL PRIMARY KEY,
    job_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    params JSONB,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User conversations for fine-tuning
CREATE TABLE IF NOT EXISTS api.conversations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    session_id UUID DEFAULT gen_random_uuid(),
    input_text TEXT NOT NULL,
    output_text TEXT,
    feedback_score INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Model metrics
CREATE TABLE IF NOT EXISTS api.model_metrics (
    id SERIAL PRIMARY KEY,
    model_name VARCHAR(100),
    metric_type VARCHAR(50),
    value NUMERIC,
    metadata JSONB,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create views for API access
CREATE OR REPLACE VIEW api.hello AS
    SELECT content FROM api.messages WHERE id = 1;

-- Function for RAG search
CREATE OR REPLACE FUNCTION api.search_documents(query_text TEXT, limit_count INTEGER DEFAULT 5)
RETURNS TABLE(
    id INTEGER,
    title TEXT,
    content TEXT,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id,
        d.title,
        d.content,
        1 - (d.embedding <=> pgml.embed('sentence-transformers/all-MiniLM-L6-v2', query_text))::float AS similarity
    FROM api.rag_documents d
    WHERE d.embedding IS NOT NULL
    ORDER BY d.embedding <=> pgml.embed('sentence-transformers/all-MiniLM-L6-v2', query_text)
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function to trigger model fine-tuning
CREATE OR REPLACE FUNCTION api.schedule_training(job_type TEXT, params JSONB DEFAULT '{}')
RETURNS api.training_jobs AS $$
DECLARE
    new_job api.training_jobs;
BEGIN
    INSERT INTO api.training_jobs (job_type, status, params)
    VALUES (job_type, 'pending', params)
    RETURNING * INTO new_job;
    
    -- Trigger notification for scheduler
    PERFORM pg_notify('training_job', json_build_object(
        'job_id', new_job.id,
        'job_type', new_job.job_type
    )::text);
    
    RETURN new_job;
END;
$$ LANGUAGE plpgsql;

-- Function to process training job (called by scheduler)
CREATE OR REPLACE FUNCTION api.process_training_job(job_id INTEGER)
RETURNS VOID AS $$
DECLARE
    job api.training_jobs;
BEGIN
    SELECT * INTO job FROM api.training_jobs WHERE id = job_id;
    
    IF job.status != 'pending' THEN
        RETURN;
    END IF;
    
    UPDATE api.training_jobs 
    SET status = 'processing', started_at = CURRENT_TIMESTAMP
    WHERE id = job_id;
    
    -- Simulate training based on job type
    CASE job.job_type
        WHEN 'fine_tune' THEN
            -- Fine-tune model on conversation data
            PERFORM pgml.train(
                project_name => 'poolside_model',
                task => 'text-generation',
                relation_name => 'api.conversations',
                y_column_name => 'output_text',
                algorithm => 'linear',
                hyperparams => '{"max_iter": 100}'::jsonb
            );
        WHEN 'embed_documents' THEN
            -- Generate embeddings for new documents
            UPDATE api.rag_documents
            SET embedding = pgml.embed('sentence-transformers/all-MiniLM-L6-v2', content)
            WHERE embedding IS NULL;
        ELSE
            RAISE EXCEPTION 'Unknown job type: %', job.job_type;
    END CASE;
    
    UPDATE api.training_jobs 
    SET status = 'completed', completed_at = CURRENT_TIMESTAMP
    WHERE id = job_id;
    
EXCEPTION
    WHEN OTHERS THEN
        UPDATE api.training_jobs 
        SET status = 'failed', 
            completed_at = CURRENT_TIMESTAMP,
            error_message = SQLERRM
        WHERE id = job_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT SELECT ON api.messages TO web_anon;
GRANT SELECT ON api.hello TO web_anon;
GRANT SELECT ON api.rag_documents TO web_anon;
GRANT SELECT, INSERT ON api.conversations TO web_anon;
GRANT SELECT ON api.model_metrics TO web_anon;
GRANT SELECT, INSERT ON api.training_jobs TO web_anon;
GRANT EXECUTE ON FUNCTION api.search_documents TO web_anon;
GRANT EXECUTE ON FUNCTION api.schedule_training TO web_anon;

-- Create indexes for performance
CREATE INDEX idx_rag_embedding ON api.rag_documents USING ivfflat (embedding vector_cosine_ops);
CREATE INDEX idx_conversations_created ON api.conversations(created_at DESC);
CREATE INDEX idx_training_jobs_status ON api.training_jobs(status);
CREATE INDEX idx_model_metrics_time ON api.model_metrics(recorded_at DESC);

-- Schedule background jobs using pg_cron
-- Process training jobs every hour
SELECT cron.schedule('process-training-jobs', '0 * * * *', $$
    SELECT api.process_training_job(id) 
    FROM api.training_jobs 
    WHERE status = 'pending' 
    LIMIT 1;
$$);

-- Generate embeddings for new documents every 30 minutes
SELECT cron.schedule('generate-embeddings', '*/30 * * * *', $$
    UPDATE api.rag_documents 
    SET embedding = pgml.embed('sentence-transformers/all-MiniLM-L6-v2', content) 
    WHERE embedding IS NULL 
    LIMIT 100;
$$);

-- Clean up old metrics daily at 2 AM
SELECT cron.schedule('cleanup-metrics', '0 2 * * *', $$
    DELETE FROM api.model_metrics 
    WHERE recorded_at < NOW() - INTERVAL '30 days';
$$);

-- Fine-tune model weekly (Sunday at 3 AM) if there's enough new data
SELECT cron.schedule('weekly-fine-tune', '0 3 * * 0', $$
    INSERT INTO api.training_jobs (job_type, params) 
    SELECT 'fine_tune', '{"auto": true}'::jsonb 
    WHERE (SELECT COUNT(*) FROM api.conversations WHERE created_at > NOW() - INTERVAL '7 days') > 100;
$$);
