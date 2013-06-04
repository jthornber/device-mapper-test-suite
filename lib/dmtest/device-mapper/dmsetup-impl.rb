module DM::LowLevel
  # Here's an implementation for the leaf instructions that uses
  # dmsetup.
  class DMSetupImpl
    def instr_create(name)
      dmsetup('create', name)
    end

    def instr_remove(name)
      dmsetup('remove', name)
    end

    def instr_suspend(name)
      dmsetup('suspend', name)
    end

    def instr_resume(name)
      dmsetup('resume', name)
    end

    def instr_load(name, table)
      Utils::with_temp_file('dm_table') do |file|
        file.write(table)
        file.flush
        dmsetup('load', name, file.path)
      end
    end

    def instr_clear(name)
      dmsetup('clear', name)
    end

    def instr_message(name, offset, msg)
      dmsetup('message', name, msg)
    end

    def instr_wait(name, event_nr)
      dmsetup('wait', name, event_nr)
    end
  end
end
