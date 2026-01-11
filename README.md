# PropLync Backend

A minimal Quarkus backend for handling chatbot requests for the PropLync.ai platform.

## Overview

This backend service handles communication with OpenAI's ChatKit API, providing a RESTful interface for the PropLync frontend. It replaces the previous Supabase Edge Functions implementation.

## Features

- RESTful API endpoint for chatbot messages
- Integration with OpenAI ChatKit API
- Fallback to Chat Completions API if ChatKit fails
- CORS support for frontend communication
- Session management for chat conversations

## Prerequisites

- Java 17 or higher
- Maven 3.8+
- OpenAI API key

## Configuration

Set the OpenAI API key as an environment variable:

```bash
export OPENAI_API_KEY=your-api-key-here
```

Or create a `.env` file in the project root:

```
OPENAI_API_KEY=your-api-key-here
```

## Running the Application

### Development Mode

```bash
mvn quarkus:dev
```

The application will be available at `http://localhost:8080`

### Production Build

```bash
mvn clean package
java -jar target/quarkus-app/quarkus-run.jar
```

## API Endpoints

### POST /api/chatbot/message

Send a message to the chatbot.

**Request Body:**
```json
{
  "messages": [
    {
      "role": "user",
      "content": "What can you help me with?"
    }
  ],
  "sessionId": "optional-session-id"
}
```

**Response:**
```json
{
  "content": "I'm your AI Financial Copilot...",
  "workflowId": "wf_6907b12d71208190aebedcd7523c1d8d0a79856e2c61f448",
  "fallback": false
}
```

## Architecture

The backend uses:
- **Quarkus** - Supersonic Subatomic Java framework
- **RESTEasy Reactive** - JAX-RS implementation
- **Java HTTP Client** - For OpenAI API communication

## Development

### Project Structure

```
proplync-backend/
├── src/
│   ├── main/
│   │   ├── java/ai/proplync/backend/
│   │   │   └── ChatbotResource.java
│   │   └── resources/
│   │       └── application.properties
│   └── test/
├── pom.xml
└── README.md
```

## Environment Variables

- `OPENAI_API_KEY` - Required. Your OpenAI API key for ChatKit access.

## CORS Configuration

The backend is configured to accept requests from:
- `http://localhost:5173` (Vite default)
- `http://localhost:3000` (Common React port)
- `http://localhost:5174` (Alternative Vite port)

To add more origins, update `quarkus.http.cors.origins` in `application.properties`.

## License

Proprietary - PropLync.ai
