package ai.proplync.backend;

import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.URI;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;

@Path("/api/chatbot")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class ChatbotResource {

    private static final Logger LOG = Logger.getLogger(ChatbotResource.class);
    private static final String WORKFLOW_ID = "wf_6907b12d71208190aebedcd7523c1d8d0a79856e2c61f448";
    private static final String CHATKIT_API_BASE = "https://api.openai.com";

    @ConfigProperty(name = "openai.api.key")
    String openaiApiKey;

    private final HttpClient httpClient;

    @Inject
    public ChatbotResource() {
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .build();
    }

    @POST
    @Path("/message")
    public Response sendMessage(ChatbotRequest request) {
        if (openaiApiKey == null || openaiApiKey.isBlank()) {
            LOG.error("OPENAI_API_KEY is not configured");
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(Map.of("error", "OpenAI API key not configured"))
                    .build();
        }

        try {
            LOG.infof("Processing message for workflow: %s", WORKFLOW_ID);
            LOG.infof("Session ID: %s", request.sessionId != null ? request.sessionId : "new session");

            // Step 1: Create or use existing ChatKit session
            String clientSecret = createChatKitSession(request.sessionId);

            // Step 2: Send message using ChatKit Messages API
            String responseContent = sendChatKitMessage(clientSecret, request.messages);

            ChatbotResponse response = new ChatbotResponse();
            response.content = responseContent;
            response.workflowId = WORKFLOW_ID;

            return Response.ok(response).build();

        } catch (Exception e) {
            LOG.error("Error processing chatbot message", e);
            
            // Fallback to direct Chat Completions API
            try {
                String fallbackContent = fallbackToChatCompletions(request.messages);
                ChatbotResponse response = new ChatbotResponse();
                response.content = fallbackContent;
                response.fallback = true;
                return Response.ok(response).build();
            } catch (Exception fallbackError) {
                LOG.error("Fallback also failed", fallbackError);
                return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                        .entity(Map.of("error", fallbackError.getMessage()))
                        .build();
            }
        }
    }

    private String createChatKitSession(String sessionId) throws Exception {
        LOG.info("Creating ChatKit session...");
        
        String userId = sessionId != null ? sessionId : "user_" + System.currentTimeMillis();
        
        String requestBody = String.format(
            "{\"workflow\":{\"id\":\"%s\"},\"user\":\"%s\"}",
            WORKFLOW_ID, userId
        );

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(CHATKIT_API_BASE + "/v1/chatkit/sessions"))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + openaiApiKey)
                .header("OpenAI-Beta", "chatkit_beta=v1")
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .timeout(Duration.ofSeconds(30))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            LOG.errorf("Session creation failed: %d - %s", response.statusCode(), response.body());
            throw new RuntimeException("Session creation failed: " + response.statusCode());
        }

        // Parse JSON response to get client_secret
        String responseBody = response.body();
        // Simple JSON parsing - in production, use a proper JSON library
        int secretIndex = responseBody.indexOf("\"client_secret\":\"");
        if (secretIndex == -1) {
            throw new RuntimeException("Could not find client_secret in response");
        }
        int start = secretIndex + "\"client_secret\":\"".length();
        int end = responseBody.indexOf("\"", start);
        String clientSecret = responseBody.substring(start, end);
        
        LOG.info("Session created, client_secret obtained");
        return clientSecret;
    }

    private String sendChatKitMessage(String clientSecret, Message[] messages) throws Exception {
        LOG.info("Sending message via ChatKit API...");
        
        if (messages == null || messages.length == 0) {
            throw new IllegalArgumentException("Messages array is empty");
        }
        
        Message lastMessage = messages[messages.length - 1];
        
        String requestBody = String.format(
            "{\"content\":\"%s\",\"role\":\"user\"}",
            escapeJson(lastMessage.content)
        );

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(CHATKIT_API_BASE + "/v1/chatkit/messages"))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + clientSecret)
                .header("OpenAI-Beta", "chatkit_beta=v1")
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .timeout(Duration.ofSeconds(60))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            LOG.errorf("ChatKit message API failed: %d - %s", response.statusCode(), response.body());
            throw new RuntimeException("ChatKit message API failed: " + response.statusCode());
        }

        // Process streaming response
        String responseBody = response.body();
        return processStreamingResponse(responseBody);
    }

    private String processStreamingResponse(String responseBody) {
        StringBuilder fullContent = new StringBuilder();
        String[] lines = responseBody.split("\n");
        
        for (String line : lines) {
            if (line.startsWith("data: ")) {
                String jsonStr = line.substring(6).trim();
                if ("[DONE]".equals(jsonStr)) {
                    continue;
                }
                
                try {
                    // Simple parsing - extract content from delta
                    int deltaIndex = jsonStr.indexOf("\"delta\":");
                    if (deltaIndex != -1) {
                        int contentIndex = jsonStr.indexOf("\"content\":\"", deltaIndex);
                        if (contentIndex != -1) {
                            int start = contentIndex + "\"content\":\"".length();
                            int end = jsonStr.indexOf("\"", start);
                            if (end > start) {
                                String content = jsonStr.substring(start, end);
                                fullContent.append(unescapeJson(content));
                            }
                        }
                    }
                } catch (Exception e) {
                    LOG.debugf("Error parsing streaming chunk: %s", e.getMessage());
                }
            }
        }

        String result = fullContent.toString();
        if (result.isEmpty()) {
            return "I received your message but couldn't generate a response.";
        }
        
        LOG.info("Response received via ChatKit workflow");
        return result;
    }

    private String fallbackToChatCompletions(Message[] messages) throws Exception {
        LOG.info("Using fallback Chat Completions API");
        
        StringBuilder messagesJson = new StringBuilder();
        messagesJson.append("{\"role\":\"system\",\"content\":\"You are an AI Financial Copilot for PropLync.ai, a real estate investment platform. You help users analyze properties across Europe, calculate ROI for different rental strategies (Short-Term, Long-Term, Rent-to-Buy), understand local regulations, and find the best investment opportunities. Provide clear, actionable financial advice and insights. Be professional yet friendly.\"}");
        
        for (Message msg : messages) {
            messagesJson.append(",{\"role\":\"").append(msg.role).append("\",\"content\":\"")
                    .append(escapeJson(msg.content)).append("\"}");
        }
        
        String requestBody = String.format(
            "{\"model\":\"gpt-4o-mini\",\"messages\":[%s]}",
            messagesJson.toString()
        );

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("https://api.openai.com/v1/chat/completions"))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + openaiApiKey)
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .timeout(Duration.ofSeconds(60))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            LOG.errorf("Fallback API error: %d - %s", response.statusCode(), response.body());
            throw new RuntimeException("Fallback API error: " + response.statusCode());
        }

        // Parse response to get content
        String responseBody = response.body();
        int contentIndex = responseBody.indexOf("\"content\":\"");
        if (contentIndex == -1) {
            throw new RuntimeException("Could not find content in response");
        }
        int start = contentIndex + "\"content\":\"".length();
        int end = responseBody.indexOf("\"", start);
        return unescapeJson(responseBody.substring(start, end));
    }

    private String escapeJson(String str) {
        if (str == null) return "";
        return str.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private String unescapeJson(String str) {
        if (str == null) return "";
        return str.replace("\\\"", "\"")
                .replace("\\\\", "\\")
                .replace("\\n", "\n")
                .replace("\\r", "\r")
                .replace("\\t", "\t");
    }

    public static class ChatbotRequest {
        public Message[] messages;
        public String sessionId;
    }

    public static class Message {
        public String role;
        public String content;
    }

    public static class ChatbotResponse {
        public String content;
        public String workflowId;
        public Boolean fallback;
    }
}
