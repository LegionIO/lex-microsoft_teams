# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module AdaptiveCards
          def build_card(body:, actions: [], version: '1.4', **)
            card = {
              '$schema' => 'http://adaptivecards.io/schemas/adaptive-card.json',
              'type'    => 'AdaptiveCard',
              'version' => version,
              'body'    => body
            }
            card['actions'] = actions unless actions.empty?
            { result: card }
          end

          def text_block(text:, size: 'default', weight: 'default', wrap: true, **)
            block = { type: 'TextBlock', text: text, wrap: wrap }
            block[:size] = size unless size == 'default'
            block[:weight] = weight unless weight == 'default'
            { result: block }
          end

          def fact_set(facts:, **)
            {
              result: {
                type:  'FactSet',
                facts: facts.map { |title, value| { title: title.to_s, value: value.to_s } }
              }
            }
          end

          def action_open_url(title:, url:, **)
            { result: { type: 'Action.OpenUrl', title: title, url: url } }
          end

          def action_submit(title:, data: {}, **)
            { result: { type: 'Action.Submit', title: title, data: data } }
          end

          def message_attachment(card:, **)
            {
              result: {
                contentType: 'application/vnd.microsoft.card.adaptive',
                contentUrl:  nil,
                content:     card
              }
            }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
