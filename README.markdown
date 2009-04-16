Exception Collection
====================

My first AppEngine app. It collects exceptions in Rails apps, ala Hoptoad and Exceptional,
but has about 10% of the features.

Installation
------------

Get JRuby and some gems...

    git clone git://github.com/jruby/jruby.git
    cd jruby
    ant && ant jar-complete
    bin/jruby -S gem install rake sinatra haml warbler
    
Download Exception Collection and run warbler to get the tmp/war directory...

    git clone git://github.com/seven1m/exceptioncollection.git
    cd exceptioncollection
    PATH_TO_JRUBY/bin/jruby -S warble

Go to tmp/war/WEB-INF/gems/gems/sinatra-0.9.1.1/lib/sinatra.rb and commend
out the last line which is `use_in_file_templates!`.

Upload to Google AppEngine or test locally with the AppEngine SDK.
