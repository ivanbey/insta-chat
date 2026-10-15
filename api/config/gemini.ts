import { GoogleGenerativeAI } from '@google/generative-ai';

const apiKey = process.env.GEMINI_API_KEY || '';

if (!apiKey) {
  console.warn('Advertencia: GEMINI_API_KEY no configurada en las variables de entorno.');
}

export const ai = new GoogleGenerativeAI(apiKey);

export const GEMINI_EMBEDDING_MODEL = process.env.GEMINI_EMBEDDING_MODEL || 'text-embedding-004';
export const GEMINI_GENERATIVE_MODEL = process.env.GEMINI_GENERATIVE_MODEL || 'gemini-1.5-flash';
