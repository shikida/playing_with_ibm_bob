#!/usr/bin/env node

/**
 * Slack MCP Server
 * Implements Slack API integration via MCP tools:
 * - Send messages to Slack channels
 * - Read message history from Slack channels
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import axios from "axios";

/**
 * Slack Bot Token - should be configured via environment variable
 * Default token from slack.txt for testing
 */
const SLACK_TOKEN = process.env.SLACK_BOT_TOKEN || "<YOUR SLACK TOKEN HERE>";

/**
 * Create an MCP server with Slack integration capabilities
 */
const server = new Server(
  {
    name: "slack-mcp",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

/**
 * Handler that lists available Slack tools
 */
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "send_slack_message",
        description: "Send a message to a Slack channel",
        inputSchema: {
          type: "object",
          properties: {
            channel: {
              type: "string",
              description: "Channel name or channel ID"
            },
            text: {
              type: "string",
              description: "Message text to send"
            }
          },
          required: ["channel", "text"]
        }
      },
      {
        name: "read_slack_messages",
        description: "Read message history from a Slack channel",
        inputSchema: {
          type: "object",
          properties: {
            channel: {
              type: "string",
              description: "Channel ID"
            },
            limit: {
              type: "number",
              description: "Number of messages to retrieve (default: 10)",
              default: 10
            }
          },
          required: ["channel"]
        }
      }
    ]
  };
});

/**
 * Handler for Slack tool calls
 */
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  switch (request.params.name) {
    case "send_slack_message": {
      const channel = String(request.params.arguments?.channel);
      const text = String(request.params.arguments?.text);
      
      if (!channel || !text) {
        throw new Error("Channel and text are required");
      }

      try {
        const response = await axios.post(
          "https://slack.com/api/chat.postMessage",
          {
            channel: channel,
            text: text
          },
          {
            headers: {
              "Authorization": `Bearer ${SLACK_TOKEN}`,
              "Content-Type": "application/json; charset=utf-8"
            }
          }
        );

        if (!response.data.ok) {
          throw new Error(`Slack API error: ${response.data.error}`);
        }

        return {
          content: [{
            type: "text",
            text: `Message sent successfully to ${channel}\nTimestamp: ${response.data.ts}`
          }]
        };
      } catch (error) {
        if (axios.isAxiosError(error)) {
          throw new Error(`Failed to send message: ${error.message}`);
        }
        throw error;
      }
    }

    case "read_slack_messages": {
      const channel = String(request.params.arguments?.channel);
      const limit = Number(request.params.arguments?.limit) || 10;
      
      if (!channel) {
        throw new Error("Channel is required");
      }

      try {
        const response = await axios.get(
          `https://slack.com/api/conversations.history`,
          {
            params: {
              channel: channel,
              limit: limit
            },
            headers: {
              "Authorization": `Bearer ${SLACK_TOKEN}`
            }
          }
        );

        if (!response.data.ok) {
          throw new Error(`Slack API error: ${response.data.error}`);
        }

        const messages = response.data.messages || [];
        const formattedMessages = messages.map((msg: any, index: number) => {
          const timestamp = new Date(parseFloat(msg.ts) * 1000).toISOString();
          return `[${index + 1}] ${timestamp}\nUser: ${msg.user || 'Unknown'}\nText: ${msg.text || '(no text)'}`;
        }).join('\n\n');

        return {
          content: [{
            type: "text",
            text: `Retrieved ${messages.length} messages from ${channel}:\n\n${formattedMessages}`
          }]
        };
      } catch (error) {
        if (axios.isAxiosError(error)) {
          throw new Error(`Failed to read messages: ${error.message}`);
        }
        throw error;
      }
    }

    default:
      throw new Error(`Unknown tool: ${request.params.name}`);
  }
});

/**
 * Start the server using stdio transport
 */
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Slack MCP server running on stdio");
}

main().catch((error) => {
  console.error("Server error:", error);
  process.exit(1);
});

// Made with Bob
