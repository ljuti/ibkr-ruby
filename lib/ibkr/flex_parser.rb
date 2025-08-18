# frozen_string_literal: true

require "ox"

module Ibkr
  class FlexParser
    def self.parse(xml_string)
      new.parse(xml_string)
    end

    def parse(xml_string)
      # Remove XML declaration if present
      clean_xml = xml_string.sub(/\A<\?xml[^>]*\?>\s*/m, '')
      doc = Ox.parse(clean_xml)
      return {} if doc.nil? || !doc.respond_to?(:name) || doc.name.nil?
      { doc.name.to_sym => parse_element(doc) }
    end

    private

    def parse_element(element)
      return element unless element.is_a?(Ox::Element)

      # Extract attributes
      attrs = element.attributes.transform_keys(&:to_sym) if element.respond_to?(:attributes)
      
      # Extract child nodes
      children = {}
      text_content = nil
      
      element.nodes&.each do |node|
        case node
        when String
          text_content = node.strip unless node.strip.empty?
        when Ox::Element
          key = node.name.to_sym
          value = parse_element(node)
          
          if children[key]
            # Convert to array if multiple elements with same name
            children[key] = [children[key]] unless children[key].is_a?(Array)
            children[key] << value
          else
            children[key] = value
          end
        end
      end
      
      # Return appropriate structure
      if children.empty? && attrs.nil?
        text_content
      elsif children.empty? && text_content
        attrs ? attrs.merge(value: text_content) : text_content
      elsif attrs && !children.empty?
        attrs.merge(children)
      elsif !children.empty?
        children
      else
        attrs || {}
      end
    end
  end
end