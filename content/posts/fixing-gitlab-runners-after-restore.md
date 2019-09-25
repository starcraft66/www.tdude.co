---
title: "Fixing GitLab runners after restoring from backup without secrets with minimal data loss"
date: 2019-09-25T16:48:14-04:00
---

Every now and then comes a time when services need to be migrated from old hosts to new hosts.

A few months ago, I migrated my personal GitLab instance from one server to another. GitLab has excellent documentation on how to perform backup and restore operations on self-hosted GitLab instances. Unfortunately, I was not so excellent at reading said instructions and ended up making a small but big mistake when restoring the GitLab backup taken from my old server onto the new server. I forgot to copy the `gitlab-secrets.json` file before restarting GitLab after restoring the backup.

Upon starting GitLab, a new `gitlab-secrets.json` file was created with new encryption keys and my GitLab database ended up in an inconsistent state where stuff was encrypted with two different private keys. I eventually found out about this and restored my backed-up `gitlab-secrets.json` file but it was too late, stuff was already starting to break, notably my gitlab runners status page was returning an HTTP 500 error and my runners were unable to communicate build status back to GitLab.

My runners were showing errors that looked like this:

```
WARNING: Appending trace to coordinator... failed   code=500 job=59435 job-log= job-status= runner=******** sent-log=0-501 status=500 Internal Server Error
WARNING: Appending trace to coordinator... failed   code=500 job=59435 job-log= job-status= runner=******** sent-log=0-501 status=500 Internal Server Error
```

Gitlab was showing errors that looked like this:

```
Started PATCH "/api/v4/jobs/59435/trace" for runner at 2019-09-01 15:21:22 +0300
Processing by Gitlab::RequestForgeryProtection::Controller#index as HTML
Can't verify CSRF token authenticity.
This CSRF token verification failure is handled internally by `GitLab::RequestForgeryProtection`
Unlike the logs may suggest, this does not result in an actual 422 response to the user
For API requests, the only effect is that `current_user` will be `nil` for the duration of the request
Completed 422 Unprocessable Entity in 1ms (ActiveRecord: 0.0ms)

OpenSSL::Cipher::CipherError ():
  /opt/gitlab/embedded/lib/ruby/gems/2.6.0/gems/encryptor-3.0.0/lib/encryptor.rb:98:in `final'
  /opt/gitlab/embedded/lib/ruby/gems/2.6.0/gems/encryptor-3.0.0/lib/encryptor.rb:98:in `crypt'
  /opt/gitlab/embedded/lib/ruby/gems/2.6.0/gems/encryptor-3.0.0/lib/encryptor.rb:49:in `decrypt'
  /opt/gitlab/embedded/service/gitlab-rails/lib/gitlab/crypto_helper.rb:27:in `aes256_gcm_decrypt'
[...]
```

Now, GitLab has [instructions](https://docs.gitlab.com/ee/raketasks/backup_restore.html#when-the-secrets-file-is-lost) on how to proceed if you lose your `gitlab-secrets.json` file which involves pretty much getting rid of any encrypted data in your database and starting fresh. I didn't want to delete everything from my database, I just wanted to get rid of the small amount of data that was encrypted with the wrong private keys.

Fortunately, after lots of Google-fu, I was able to locate a [ruby script](https://gitlab.com/gitlab-org/gitlab-foss/issues/58524#note_202417144) someone who works for GitLab wrote for a customer to correct the exact issue I was experiencing!

The solution was as simple as spawning a `gitlab-rails` console and pasting the following script in!

For omnibus installations, you can spawn a rails console by running `sudo gitlab-rails console`. For docker installations, simply execute that command inside the gitlab container: `docker exec -it <container name> gitlab-rails console`.

The script to paste in:
```ruby
table_column_combos = [
    [Namespace, "runners_token_encrypted", "runners_token"],
    [Project, "runners_token_encrypted", "runners_token"],
    [Ci::Build, "token_encrypted", "token"],
    [Ci::Runner, "token_encrypted", "token"],
    [ApplicationSetting, "runners_registration_token_encrypted", "runners_registration_token"],
    [Group, "runners_token_encrypted"],
]


table_column_combos.each do |table,column,column2|
  total = 0
  fixed = 0
  removed = 0
  bad = []
  table.find_each do |data|
    begin
      total += 1
      ::Gitlab::CryptoHelper.aes256_gcm_decrypt(data[column])
    rescue => e
      if data[column2].to_s.empty?
        puts "Bad Value column2 is empty: #{data[column]}"
        data[column] = nil
        #data.save()
        removed += 1
      else
        puts "Bad Value: #{data[column]}"
        data[column] = ::Gitlab::CryptoHelper.aes256_gcm_encrypt(data[column2])
        #data.save()
        fixed += 1
      end
      bad << data
    end
  end
  puts "Table: #{table.name}    Bad #{bad.length} / Good #{total}, Fixed #{fixed}, Removed #{removed}"
end
```

Once you hit enter, the script should output that if found a bunch of bad values and fixed them.
```
Bad Value column2 is empty: sdjfksjdfksduhfefgiwuefgoqwuehfoweuhfoweihfoewih 
...
```

At this point, all that is left to do is to restart GitLab. Once restarted, I was able to access my runners admin page and all of my GitLab CI pipelines started working again! Finding this script really helped me out so I figured I would spread the knowledge for anyone else stuck in my original situation.