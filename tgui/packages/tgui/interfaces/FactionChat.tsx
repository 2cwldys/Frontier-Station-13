import { Box, Button, NoticeBox, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type ChatMessage = { sender: string; message: string; sent_at: string };

type FactionChatData = {
  is_member: BooleanLike;
  faction_name: string | null;
  page: number;
  messages: ChatMessage[];
  db_error: BooleanLike;
};

export const FactionChat = (props) => {
  const { act, data } = useBackend<FactionChatData>();
  const [draft, setDraft] = useState('');

  if (!data.is_member) {
    return (
      <NtosWindow width={420} height={300}>
        <NtosWindow.Content>
          <Section title="Faction Chat">
            <Box color="bad">
              You need a faction-issued ID with a real job assignment to use
              this.
            </Box>
          </Section>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  const send = () => {
    if (draft.trim()) {
      act('send', { message: draft });
      setDraft('');
    }
  };

  return (
    <NtosWindow width={420} height={480}>
      <NtosWindow.Content scrollable>
        <Section
          title={`Faction Chat -- ${data.faction_name}`}
          buttons={
            <>
              <Button
                icon="chevron-left"
                disabled={data.page <= 0}
                onClick={() => act('prev_page')}
              />
              <Button icon="chevron-right" onClick={() => act('next_page')} />
            </>
          }
        >
          {!!data.db_error && (
            <NoticeBox danger>
              Database error -- messages may be missing or failed to send.
            </NoticeBox>
          )}
          {data.messages
            .slice()
            .reverse()
            .map((m, i) => (
              <Box key={i} mb={0.5}>
                <Box bold inline>
                  {m.sender}:
                </Box>{' '}
                {m.message}
                <Box color="label" fontSize="0.8em">
                  {m.sent_at}
                </Box>
              </Box>
            ))}
        </Section>
        <Section>
          <input
            style={{ width: '100%' }}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && send()}
          />
          <Button mt={0.5} disabled={!draft.trim()} onClick={send}>
            Send
          </Button>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
