-- 1. Habilitar la extensión pgvector
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- 2. Tabla de Empresas (Tenants)
CREATE TABLE public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    similarity_threshold FLOAT NOT NULL DEFAULT 0.78,
    max_context_chunks INT NOT NULL DEFAULT 4,
    system_prompt_custom TEXT,
    fallback_message TEXT NOT NULL DEFAULT 'No dispongo de esa información específica. Puedes consultar directamente con el equipo de la empresa.',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Cuentas de Instagram vinculadas
CREATE TABLE public.instagram_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    instagram_business_account_id VARCHAR(255) NOT NULL UNIQUE,
    facebook_page_id VARCHAR(255) NOT NULL,
    page_access_token TEXT NOT NULL,
    account_name VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Documentos cargados por la empresa
CREATE TABLE public.documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    file_path TEXT,
    file_type VARCHAR(50) NOT NULL, -- 'pdf', 'manual_text', 'faq'
    file_size_bytes BIGINT,
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Fragmentos de documentos y Embeddings (768 dimensiones para text-embedding-004 de Gemini)
CREATE TABLE public.document_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID REFERENCES public.documents(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    embedding extensions.vector(768) NOT NULL,
    chunk_index INT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice HNSW para búsqueda rápida por similitud coseno
CREATE INDEX idx_document_chunks_embedding_hnsw 
ON public.document_chunks 
USING hnsw (embedding extensions.vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

CREATE INDEX idx_document_chunks_company ON public.document_chunks(company_id, is_active);

-- 6. Conversaciones
CREATE TABLE public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    instagram_scoped_user_id VARCHAR(255) NOT NULL,
    last_interaction_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(company_id, instagram_scoped_user_id)
);

-- 7. Mensajes de la Conversación
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    meta_message_id VARCHAR(255) UNIQUE, -- Para deduplicación
    sender_type VARCHAR(20) NOT NULL, -- 'user', 'bot', 'human_agent'
    content TEXT NOT NULL,
    similarity_score FLOAT,
    context_chunks_used JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. Logs de Errores y Auditoría
CREATE TABLE public.error_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    source VARCHAR(100) NOT NULL,
    error_message TEXT NOT NULL,
    stack_trace TEXT,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. Función RPC para Búsqueda Vectorial por Similitud Coseno con Umbral τ
CREATE OR REPLACE FUNCTION public.match_document_chunks(
    query_embedding extensions.vector(768),
    match_threshold FLOAT,
    match_count INT,
    filter_company_id UUID
)
RETURNS TABLE (
    id UUID,
    document_id UUID,
    content TEXT,
    similarity FLOAT,
    metadata JSONB
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        dc.id,
        dc.document_id,
        dc.content,
        (1 - (dc.embedding <=> query_embedding))::FLOAT AS similarity,
        dc.metadata
    FROM public.document_chunks dc
    WHERE dc.company_id = filter_company_id
      AND dc.is_active = true
      AND (1 - (dc.embedding <=> query_embedding)) >= match_threshold
    ORDER BY dc.embedding <=> query_embedding ASC
    LIMIT match_count;
END;
$$;

-- 10. Seguridad Row Level Security (RLS)
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instagram_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_logs ENABLE ROW LEVEL SECURITY;

-- Política RLS base: El usuario autenticado solo accede a datos de su empresa asignada
CREATE POLICY "Acceso por empresa del usuario - companies" ON public.companies
    FOR ALL USING (id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Acceso por empresa del usuario - instagram_accounts" ON public.instagram_accounts
    FOR ALL USING (company_id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Acceso por empresa del usuario - documents" ON public.documents
    FOR ALL USING (company_id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Acceso por empresa del usuario - document_chunks" ON public.document_chunks
    FOR ALL USING (company_id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Acceso por empresa del usuario - conversations" ON public.conversations
    FOR ALL USING (company_id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Acceso por empresa del usuario - messages" ON public.messages
    FOR ALL USING (company_id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);

CREATE POLICY "Acceso por empresa del usuario - error_logs" ON public.error_logs
    FOR ALL USING (company_id = (auth.jwt() -> 'user_metadata' ->> 'company_id')::uuid);
