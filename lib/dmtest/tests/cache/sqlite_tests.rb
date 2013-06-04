require 'config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class SQLiteTests < ThinpTestCase
  include Tags
  include Utils

  def setup
    super
    @data_block_size = 2048
  end

  def drop_caches
    ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')
  end

  #----------------------------------------------------------------
  # SQLITE tests
  # FIXME: move to separate suite?
  #----------------------------------------------------------------

  def sql_create_table
    "CREATE TABLE t1(a INTEGER, b INTEGER, c VARCHAR(100));\n"
  end

  def sql_drop_table
    "DROP TABLE t1;\n"
  end

  def sql_begin
    "BEGIN;"
  end

  def sql_commit
    "COMMIT;"
  end

  def sql_transaction(count = nil, &block)
    sql = sql_begin
    sql += yield
    sql += sql_commit
    sql
  end

  def sql_create_inserts(count = nil, start = nil)
    count = 12500 if count.nil?
    start = 0 if start.nil?
    sql = ""

    for i in start..count
      v = rand(999999999).to_i
      s = number_to_string(v)
      sql += "INSERT INTO t1 VALUES(#{i},#{v},\'#{s}');\n"
    end

    sql
  end

  def sql_inserts_no_transaction(count = nil)
    sql_create_table +  sql_create_inserts(count)
  end

  def sql_inserts_global_transaction(count = nil)
    sql = sql_transaction do
      sql_create_table +  sql_create_inserts(count) + sql_drop_table
    end

    sql
  end

  def sql_inserts_multiple_transaction(count = nil, fraction = nil)
    count = 12500 if count.nil?
    fraction = count / 1000 if fraction.nil?

    return "" if count / fraction < 2

    sql = sql_begin + sql_create_table

    i = 0
    while i < count do
      sql += sql_transaction { sql_create_inserts(count, fraction) }
      sql += sql_commit + sql_begin
      i += fraction
    end

    sql += sql_commit
    sql
  end

  def do_sqlite_exec(sql_script)
    STDERR.puts "Running sql script..."
    Utils::with_temp_file('.sql_script') do |sql_file|
      sql_file << sql_script
      sql_file.flush
      sql_file.close

      ProcessControl.run("cp #{sql_file.path} /tmp/run_test.sql")
      ProcessControl.run("time sqlite3 test.db < #{sql_file.path}")
      ProcessControl.run("rm -fr test.db")
    end
  end

  def with_sqlite_prepare(dev, fs_type = nil, &block)
    fs_type = :ext4 if fs_type.nil?

    fs = FS::file_system(fs_type, dev)
    STDERR.puts "formatting ..."
    fs.format

    STDERR.puts "mounting ..."
    fs.with_mount('./.sql_tests', :discard => true) do
      Dir.chdir('./.sql_tests') do
	yield
      end
    end
  end

  def with_sqlite(policy = nil, records = nil, &block)
    policy = 'mq' if policy.nil?

    with_standard_cache(:format => true, :policy => policy) do |cache|
      with_sqlite_prepare(cache, :ext4) do
        STDERR.puts "\'#{policy}\' policy\n"
        report_time("#{block} with \'#{policy}\' policy...") do
	  sql = yield(records)
          do_sqlite_exec(sql)
        end
      end
    end
  end

  def test_sqlite_insert_12k_global_transaction
    @cache_policies.each do |policy|
      with_sqlite(policy, nil) { sql_inserts_global_transaction }
    end
  end

  def test_sqlite_insert_12k_multiple_transaction
    @cache_policies.each do |policy|
      with_sqlite(policy, nil) { sql_inserts_multiple_transaction }
    end
  end

  def test_sqlite_insert_12k_no_transaction
    @cache_policies.each do |policy|
      with_sqlite(policy, nil) { sql_inserts_no_transaction }
    end
  end
end
