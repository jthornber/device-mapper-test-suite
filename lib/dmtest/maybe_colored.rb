if STDOUT.isatty
require 'colored'
else
  module Colored
    extend self

    COLORS = {
      'black'   => 30,
      'red'     => 31,
      'green'   => 32,
      'yellow'  => 33,
      'blue'    => 34,
      'magenta' => 35,
      'cyan'    => 36,
      'white'   => 37
    }

    EXTRAS = {
      'clear'     => 0,
      'bold'      => 1,
      'underline' => 4,
      'reversed'  => 7
    }

    COLORS.each do |color, value|
      define_method(color) do
        self
      end

      define_method("on_#{color}") do
        self
      end

      COLORS.each do |highlight, value|
        next if color == highlight
        define_method("#{color}_on_#{highlight}") do
          self
        end
      end
    end

    EXTRAS.each do |extra, value|
      next if extra == 'clear'
      define_method(extra) do
        self
      end
    end
  end unless Object.const_defined? :Colored

  String.send(:include, Colored)
end
