-- Create roles for PostgREST
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

-- RAG document storage (simplified - no embeddings)
CREATE TABLE IF NOT EXISTS api.rag_documents (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed some example documents
INSERT INTO api.rag_documents (title, content, metadata) VALUES
('Python Basics', 'Python is a high-level programming language. It uses indentation for code blocks and has dynamic typing.', '{"category": "programming"}'),
('JavaScript Guide', 'JavaScript is the language of the web. It runs in browsers and on servers via Node.js.', '{"category": "programming"}'),
('Docker Overview', 'Docker is a containerization platform that packages applications with their dependencies.', '{"category": "devops"}'),
('SQL Tutorial', 'SQL is used to query relational databases. Common commands include SELECT, INSERT, UPDATE, and DELETE.', '{"category": "database"}'),
('Git Commands', 'Git is a version control system. Use git commit to save changes and git push to share them.', '{"category": "devops"}');

-- User conversations
CREATE TABLE IF NOT EXISTS api.conversations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    session_id UUID DEFAULT gen_random_uuid(),
    query TEXT NOT NULL,
    response TEXT,
    context_docs INTEGER[], -- Array of document IDs used for context
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create view for API access
CREATE OR REPLACE VIEW api.hello AS
    SELECT content FROM api.messages WHERE id = 1;

-- Simple keyword-based document search function
CREATE OR REPLACE FUNCTION api.search_documents(query_text TEXT, limit_count INTEGER DEFAULT 5)
RETURNS TABLE(
    id INTEGER,
    title TEXT,
    content TEXT,
    relevance FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.id,
        d.title,
        d.content,
        -- Simple relevance scoring based on keyword matching
        (
            -- Exact phrase match in title (weighted 10x)
            CASE WHEN lower(d.title) LIKE '%' || lower(query_text) || '%' THEN 10.0 ELSE 0.0 END +
            -- Exact phrase match in content (weighted 5x)
            CASE WHEN lower(d.content) LIKE '%' || lower(query_text) || '%' THEN 5.0 ELSE 0.0 END +
            -- Count significant words (3+ chars) from query that appear in title (weighted 2x)
            (SELECT COUNT(*) FROM unnest(string_to_array(lower(query_text), ' ')) AS word
             WHERE length(word) >= 3 AND lower(d.title) LIKE '%' || word || '%') * 2.0 +
            -- Count significant words (3+ chars) from query that appear in content
            (SELECT COUNT(*) FROM unnest(string_to_array(lower(query_text), ' ')) AS word
             WHERE length(word) >= 3 AND lower(d.content) LIKE '%' || word || '%')
        )::FLOAT AS relevance
    FROM api.rag_documents d
    WHERE
        lower(d.title) LIKE '%' || lower(query_text) || '%' OR
        lower(d.content) LIKE '%' || lower(query_text) || '%' OR
        EXISTS (
            SELECT 1 FROM unnest(string_to_array(lower(query_text), ' ')) AS word
            WHERE length(word) >= 3 AND (lower(d.title) LIKE '%' || word || '%' OR lower(d.content) LIKE '%' || word || '%')
        )
    ORDER BY relevance DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get RAG response (retrieves docs but doesn't call LLM - that's done by client)
CREATE OR REPLACE FUNCTION api.rag_query(user_query TEXT, doc_limit INTEGER DEFAULT 3)
RETURNS TABLE(
    query TEXT,
    documents JSONB,
    prompt TEXT
) AS $$
DECLARE
    docs JSONB;
    context_text TEXT;
    full_prompt TEXT;
BEGIN
    -- Get relevant documents
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'content', s.content,
        'relevance', s.relevance
    ))
    INTO docs
    FROM api.search_documents(user_query, doc_limit) s;

    -- Build context from documents
    SELECT string_agg(
        format('Document %s - %s: %s', s.id, s.title, s.content),
        E'\n\n'
    )
    INTO context_text
    FROM api.search_documents(user_query, doc_limit) s;

    -- Build prompt for LLM
    full_prompt := format(
        'Context documents:
%s

User question: %s

Please answer the question based on the context documents provided above. If the context does not contain relevant information, say so.',
        COALESCE(context_text, 'No relevant documents found.'),
        user_query
    );

    RETURN QUERY SELECT
        user_query,
        COALESCE(docs, '[]'::jsonb),
        full_prompt;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT SELECT ON api.messages TO web_anon;
GRANT SELECT ON api.hello TO web_anon;
GRANT SELECT, INSERT ON api.rag_documents TO web_anon;
GRANT SELECT, INSERT ON api.conversations TO web_anon;
GRANT EXECUTE ON FUNCTION api.search_documents TO web_anon;
GRANT EXECUTE ON FUNCTION api.rag_query TO web_anon;

-- Grant sequence permissions for INSERT operations
GRANT USAGE, SELECT ON SEQUENCE api.rag_documents_id_seq TO web_anon;
GRANT USAGE, SELECT ON SEQUENCE api.conversations_id_seq TO web_anon;
GRANT USAGE, SELECT ON SEQUENCE api.messages_id_seq TO web_anon;

-- Create indexes for performance
CREATE INDEX idx_rag_title ON api.rag_documents USING gin (to_tsvector('english', title));
CREATE INDEX idx_rag_content ON api.rag_documents USING gin (to_tsvector('english', content));
CREATE INDEX idx_conversations_created ON api.conversations(created_at DESC);
