import {
  Box,
  Button,
  Input,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend, useLocalState } from '../backend';
import { NtosWindow } from '../layouts';

type InvoiceData = {
  status_message: string;
  operator_name: string | null;
  operator_account: number | null;
  faction_uid: string;
  faction_name: string | null;
  faction_registered: BooleanLike;
  is_faction_member: BooleanLike;
  has_printer: BooleanLike;
  stored_paper: number;
};

export const InvoiceProgram = (props) => {
  const { act, data } = useBackend<InvoiceData>();
  const [amount, setAmount] = useLocalState<number>('amount', 0);
  const [purpose, setPurpose] = useLocalState<string>('purpose', '');
  const [payeeType, setPayeeType] = useLocalState<string>(
    'payeeType',
    'personal',
  );

  const canFaction = data.faction_registered && data.is_faction_member;

  return (
    <NtosWindow width={430} height={420}>
      <NtosWindow.Content scrollable>
        {!!data.status_message && (
          <NoticeBox onClick={() => act('clear_status')}>
            {data.status_message}
          </NoticeBox>
        )}
        <Section title="New Invoice">
          <LabeledList>
            <LabeledList.Item label="Payable To">
              <Button
                content={`Personal${data.operator_name ? ` (${data.operator_name})` : ''}`}
                icon="user"
                selected={payeeType === 'personal'}
                disabled={!data.operator_account}
                tooltip={
                  data.operator_account
                    ? 'Payments go to your personal bank account.'
                    : 'Your ID has no linked bank account.'
                }
                onClick={() => setPayeeType('personal')}
              />
              <Button
                content={`Faction${data.faction_name ? ` (${data.faction_name})` : ''}`}
                icon="building"
                selected={payeeType === 'faction'}
                disabled={!canFaction}
                tooltip={
                  canFaction
                    ? 'Payments go to the faction account this terminal is shackled to.'
                    : 'Terminal not linked to a registered faction, or you are not a member.'
                }
                onClick={() => setPayeeType('faction')}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Amount">
              <NumberInput
                value={amount}
                minValue={1}
                maxValue={1000000}
                width={7}
                animated
                unit="电"
                step={1}
                stepPixelSize={2}
                onChange={(value) => setAmount(value)}
              />
            </LabeledList.Item>
            <LabeledList.Item label="Purpose">
              <Input
                value={purpose}
                fluid
                placeholder="Services rendered"
                onChange={(value) => setPurpose(value)}
              />
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            <Button
              content="Print Invoice"
              icon="print"
              color="green"
              disabled={
                !data.has_printer ||
                data.stored_paper <= 0 ||
                amount <= 0 ||
                (payeeType === 'faction' ? !canFaction : !data.operator_account)
              }
              tooltip={
                !data.has_printer
                  ? 'No nano printer installed.'
                  : data.stored_paper <= 0
                    ? 'Printer is out of paper.'
                    : undefined
              }
              onClick={() =>
                act('print_invoice', {
                  amount: amount,
                  purpose: purpose,
                  payee_type: payeeType,
                })
              }
            />
            &nbsp;
            <Box as="span" color="label">
              Paper: {data.stored_paper}
            </Box>
          </Box>
        </Section>
        <Section title="How It Works">
          <Box color="label">
            The printed invoice is payable by anyone: swiping an ID card pays
            from their personal account, a charge card pays from its stored
            value, and a faction charge card pays from that faction&apos;s
            bank. Paid invoices are marked green; unpaid red.
          </Box>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
