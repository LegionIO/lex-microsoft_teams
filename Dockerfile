FROM legionio/legion

COPY . /usr/src/app/lex-microsoft_teams

WORKDIR /usr/src/app/lex-microsoft_teams
RUN bundle install
