FROM ruby:3.2-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development

COPY . .

RUN chmod +x /app/entrypoint.rb

ENTRYPOINT ["/app/entrypoint.rb"]
