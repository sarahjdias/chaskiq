# frozen_string_literal: true
require 'pp'
require 'oauth2'

module MessageApis
  class Slack
    BASE_URL = 'https://slack.com'
    HEADERS = {"content-type" => "application/json"} #Suggested set? Any?

    attr_accessor :key, :secret, :access_token

    attr_accessor :keys,
                  :client,
                  :base_url #Default: 'https://api.twitter.com/'
  
    def initialize(config: {})
      @access_token = access_token
      @conn = Faraday.new request: {
        params_encoder: Faraday::FlatParamsEncoder
      }

      @package = nil

      @keys = {}
      @keys['channel'] = 'chaskiq_channel'
      @keys['consumer_key'] = config["api_key"]
      @keys['consumer_secret'] =  config["api_secret"]
      @keys['access_token'] =  config["access_token"]
      @keys['access_token_secret'] =  config["access_token_secret"]
      @keys['user_token'] = config["user_token"]
    end

    def self.process_global_hook(params)
      
      return params[:challenge] if params[:challenge]

      team_id = params["team_id"] || JSON.parse(params[:payload])["team"]["id"]

      app_package = AppPackage.find_by(name: params["provider"].capitalize)
      integration_pkg = app_package.app_package_integrations.find_by(
        external_id: team_id
      )
      response = integration_pkg.process_event(params)
    end

    def after_install
      # TODO here create the configured channel and join it
    end

    def get_api_access
      @base_url = BASE_URL

      {
        "access_token": @keys['access_token'],
        "access_token_secret": @keys['access_token_secret']
      }.with_indifferent_access
    end

    def authorize_bot!
      get_api_access
      @conn.authorization :Bearer, @keys["access_token"]
    end

    def authorize_user!
      get_api_access
      @conn.authorization :Bearer, @keys["access_token_secret"]
    end

    def oauth_client
      @oauth_client ||= OAuth2::Client.new(
        @keys['consumer_key'], 
        @keys['consumer_secret'], 
        site: 'https://slack.com',
        authorize_url: '/oauth/v2/authorize',
        token_url: '/api/oauth.v2.access'
      )
    end

    def user_client

    end

    def url(url)
      "#{BASE_URL}#{url}"
    end

    def post_message(message, blocks, options={})
      authorize_bot!

      data = {
        "channel": options[:channel] || @keys['channel'] || 'chaskiq_channel',
        "text": message,
        "blocks": blocks,
        "username": "chahaha custom",
        "icon_url":	"http://lorempixel.com/48/48"
      }

      url = url('/api/chat.postMessage')

      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      puts response.body
      puts response.status

      response
    end

    def create_channel(name='chaskiq_channel', user_ids="")
      authorize_bot!

      data = {
        "name": name,
        "user_ids": user_ids
      }

      url = url('/api/conversations.create')

      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      #puts response.body
      JSON.parse(response.body)
    end

    def join_channel(id)
      data = {
        "channel": id
      }

      url = url('/api/conversations.join')
      #@conn.authorization :Bearer, key
      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end

      JSON.parse(response.body)
    end

    def trigger(event)
      
      subject = event.eventable
      action = event.action

      case action
      when "visitors.convert" then notify_new_lead(subject)
      when "conversation.user.first.comment" then notify_added(subject)
      #when "conversations.added" then notify_added(subject)
      else
      end
    end

    def notify_added(conversation)

      authorize_bot!

      message = conversation.messages.where.not(
        authorable_type: "Agent"
      ).last
      
      text_blocks = JSON.parse(message.messageable.serialized_content)["blocks"]
      .map{|o| 
        o['text']
      }

      participant = conversation.main_participant

      base = "#{ENV['HOST']}/apps/#{conversation.app.key}"
      conversation_url = "#{base}/conversations/#{conversation.key}"
      user_url = "#{base}/users/#{conversation.key}"
      links = "*<#{user_url}|#{conversation.main_participant.display_name}>* <#{conversation_url}|view in chaskiq>"

      data = {
        "channel": @keys['channel'] || 'chaskiq_channel',
        "text": 'New conversation from Chaskiq',
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "Conversation initiated by #{links}"
            }
          },

          {
            "type": "section",
            "fields": [
              {
                "type": "mrkdwn",
                "text": "*From:* #{participant.city}"
              },
              {
                "type": "mrkdwn",
                "text": "*When:* #{I18n.l(conversation.created_at, format: :short)}"
              },
              {
                "type": "mrkdwn",
                "text": "*Seen:* #{I18n.l(participant.last_visited_at, format: :short)}"
              },
              {
                "type": "mrkdwn",
                "text": "*Device:*\n#{participant.browser} #{participant.browser_version} / #{participant.os}"
              },

              {
                "type": "mrkdwn",
                "text": "*From:*\n<#{participant.referrer} | link>"
              },

              
            ]
          },

          {
            "type": "divider"
          },

          {
            "type": "context",
            "elements": [
              {
                "type": "mrkdwn",
                "text": "Message"
              }
            ]
          },

          {
            "type": "section",
            "text": {
              "type": "plain_text",
              "text": text_blocks.first,
              "emoji": true
            }
          },

          {
            "type": "divider"
          },

          {
            "type": "actions",
            "elements": [
              {
                "type": "button",
                "text": {
                  "type": "plain_text",
                  "text": "Close",
                  "emoji": true
                },
                "value": "click_me_123"
              },
              {
                "type": "button",
                "text": {
                  "type": "plain_text",
                  "emoji": true,
                  "text": "Reply in Channel"
                },
                "style": "primary",
                "value": "reply_in_channel_#{conversation.key}"
              },
            ]
          }
        ]
      }

      url = url('/api/chat.postMessage')
      response = post_data(url, data)

      #puts response.body
      #puts response.status      
    end

    def notify_new_lead(user)
      post_message(
        "new lead!", 
        [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "a new Lead! #{user.name}"
            }
          },
          {
            "type": "divider"
          },
          {
            "type": "actions",
            "elements": [
              {
                "type": "button",
                "text": {
                  "type": "plain_text",
                  "text": "Close",
                  "emoji": true
                },
                "value": "click_me_123"
              },
              {
                "type": "button",
                "text": {
                  "type": "plain_text",
                  "text": "Reply in channel",
                  "emoji": true
                },
                "value": "click_me_123"
              }
            ]
          }
        ]
      )
    end

    # this call process event in async job
    def enqueue_process_event(params, package)
      return handle_challenge(params) if is_challenge?(params) 
      #process_event(params, package)
      HookMessageReceiverJob.perform_now(
        id: package.id, 
        params: params.permit!.to_h
      )
    end

    def process_event(params, package)

      @package = package

      return handle_incoming_event(params) if params['event']

      payload = JSON.parse(params["payload"])

      action = payload["actions"].first

      case action['value']
      when /^reply_in_channel/
         handle_reply_in_channel_action(payload)
      else
      end
    end

    def handle_incoming_event(params)
      event = params["event"]
      puts "processing slack event type: #{event['type']}"
      case event['type']
      when 'message' then process_message(event)
      end
    end

    def process_message(event)

      # TODO: add a conversation_event_type for this type
      return if event['subtype'] === "channel_join"

      conversation = @package
      .app
      .conversations
      .joins(:conversation_channels)
      .where(
        "conversation_channels.provider =? AND 
        conversation_channels.provider_channel_id =?", 
        "slack", event["channel"]
      ).first

      text = event["text"]

      return if conversation.blank?

      return if conversation.conversation_part_channel_sources
                            .find_by(message_source_id: event["ts"]).present?

      # TODO: serialize message                      
      conversation.add_message(
        from: @package.app.agents.first, #agent_required ? Agent.first : participant,
        message: {
          html_content: text,
          #serialized_content: serialized_content
        },
        provider: 'slack',
        message_source_id: event["ts"],
        check_assignment_rules: true
      )

    end

    def handle_challenge(params)
      params[:challenge]
    end

    def is_challenge?(params)
      params.keys.include?("challenge")
    end

    def oauth_authorize(app, package)
      oauth_client.auth_code.authorize_url(
        user_scope: 'chat:write,channels:history,channels:write,groups:write,mpim:write,im:write',
        scope: 'channels:history,channels:join,chat:write,channels:manage',
        redirect_uri: package.oauth_url
      )
    end

    def receive_oauth_code(params, package)
      code = params[:code]

      headers = {
        :accept => 'application/json',
        :content_type => 'application/json'
      }

      token = oauth_client.auth_code.get_token(
        code, 
        :redirect_uri => package.oauth_url, 
        :token_method => :post
      )

      token_hash = token.to_hash

      package.update(
        external_id: token_hash["team"]["id"],
        project_id: token_hash["app_id"],
        access_token: token_hash[:access_token],
        access_token_secret: token.to_hash["authed_user"]["access_token"]
      )

      true
    end

    # triggered when a new chaskiq message is created
    # will triggered just after the ws notification
    def notify_message(conversation: , part:, channel:)

      # TODO ? redis cache here for provider / channel id / part
      return if part.conversation_part_channel_sources.find_by(provider: "slack").present?
      
      blocks = blocks_transform(part) 
      
      text = !blocks.blank? ? blocks.join(" ") : part.messageable.html_content

      blocks.prepend({
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "*#{part.authorable.name}* (#{part.authorable.model_name.human}) sent a message"
        }
      })

      response = post_message(
        "new message", 
        blocks.as_json,
        {
          channel: channel
        }
      )

      response_data = JSON.parse(response.body)

      return unless response_data["ok"]

      part.conversation_part_channel_sources.create(
        provider: 'slack', 
        message_source_id: response_data["ts"] 
      )
    end

    def handle_reply_in_channel_action(payload)
      response_url = payload["response_url"]

      reply_value = payload["actions"].first["value"].gsub("reply_in_channel_", "")

      data = {
        "channel": @keys['channel'] || 'chaskiq_channel',
        "text": payload["message"]["text"],
        "blocks": [{
          "type": "context",
          "elements": [
            {
              "type": "mrkdwn",
              "text": "channel created! "
            }
          ]
        }]
      }

      create_channel_response = create_channel(
        "chaskiq-#{Time.now.to_i}", 
        payload["user"]["id"]
      )

      slack_channel_id = create_channel_response["channel"]["id"]

      conversation = @package.app.conversations.find_by(key: reply_value)
      
      return if conversation.blank?
      
      conversation.conversation_channels.create({
        provider: 'slack',
        provider_channel_id: slack_channel_id
      })

      if create_channel_response["error"].blank?

        # joins user who clicked message
        authorize_user!
        join_channel(slack_channel_id)

        # joins bot
        authorize_bot!
        join_channel(slack_channel_id)
      end

      blocks = payload["message"]["blocks"].reject{|o| 
        o["type"] == "actions"
      } + data[:blocks]

      data.merge!(
        {
          blocks: blocks
        }
      )

      response = update_reply_in_channel_message(response_url , data)
      #response.body
      
      # sync all messages
      ConversationChannelSyncJob.perform_later(
        conversation_id: conversation.id,
        app_package_id: @package.id
      )

    end

    def update_reply_in_channel_message(response_url, data )
      @conn.post do |req|
        req.url response_url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end
    end

    def blocks_transform(part)

      blocks = JSON.parse(
        part.messageable.serialized_content
      )["blocks"].map{|o| process_block(o) } rescue []

      blocks
    end

    def process_block(block)
      res = case block["type"]
      when "unstyled"
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": block['text']
          },
          "block_id": block["key"]
        }
      when "divider"
        {
			    "type": "divider"
		    }
      when "image"
        image_url = block['data']['url']
        image_url  = "#{ENV['HOST']}#{block['data']['url']}" unless block['data']['url'].include?("://")
        {
          "type": "image",
          "title": {
            "type": "plain_text",
            "text": "image1",
            "emoji": true
          },
          "image_url": image_url,
          "alt_text": "image1"
        }
      when "header-one", "header-two", "header-three", "header-four"
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "*#{block['text']}*"
          },
          "block_id": block["key"]
        } 
      else
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": block['text']
          },
          "block_id": block["key"]
        }
      end
    end

    def post_data(url, data)
      response = @conn.post do |req|
        req.url url
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
        req.body = data.to_json
      end
      response
    end

    def sync_messages_without_channel(conversation)
      
      parts = conversation.messages.includes(:conversation_part_channel_sources)
      .where.not(conversation_part_channel_sources: {
        provider: 'slack'
      }).or(
        conversation.messages.includes(:conversation_part_channel_sources)
        .where(conversation_part_channel_sources: {
          conversation_part_id: nil
        })
      )

      channel = conversation.conversation_channels.find_by(
        provider: "slack"
      )


      parts.each do |part|
        notify_message(
          conversation: conversation , 
          part: part, 
          channel: channel.provider_channel_id
        )
      end
    end

  end
end

## PLAN

=begin
 
+ usuario crea conversacion
  + se manda mensaje por canal chaskiq
    + con opcoin de responder en canal
  + recibe hook
    + se crea canal de conversacion
  + proximos mensajes se envian y reciben por ese canal


plan:

recive button chnnel , 

1. asocia channel a conversacion
2. recive mensaje con channel, checkea channel
3. crea mensaje de channel correspondiente

cuando genera mensaje desde chaskiq

1. verifica si tiene channel
2. notifica el mensaje a channel
  2.1 actualiza el mensaje con el id del mensaje
3.  si recibe mensaje de vuelta pero ya existe mensaje , skip



=end
