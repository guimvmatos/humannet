# ADR-0003: Identidade no beta por convite, verificação depois

- **Status:** aceito
- **Data:** 2026-10-03

## Contexto

A Proposta original pede CPF e verificação facial (selfie com documento) já no MVP. Pela LGPD, biometria é **dado pessoal sensível**. Guardá-la exige base legal específica, segurança reforçada e um encarregado de dados, e um vazamento seria grave. Os serviços de verificação facial também cobram por consulta. Isso é incompatível com um MVP sem orçamento e com o princípio "privacidade > performance".

## Decisão

- **Fases 0–3:** cadastro **somente por convite**.
  - Cada código vale para um uso e expira.
  - Cada usuário gera um número limitado de convites.
  - O vínculo `invited_by` forma uma rede de confiança: uma conta abusiva expõe e pode responsabilizar quem a convidou.
- **Fase 4:** verificação de identidade e idade por um **fornecedor externo**. A HumanNet guarda apenas:
  - o resultado (verificado sim/não, maioridade sim/não, data);
  - um **hash com chave secreta (HMAC) do CPF**, só para garantir uma conta por pessoa.
- A HumanNet **nunca guarda** imagem facial nem foto de documento.

## Consequências

- O crescimento no beta é lento e controlado. Isso é intencional.
- "Uma pessoa, uma conta" (R1) é garantida só socialmente até a Fase 4.
- Features que dependem de idade (check-in na Fase 3) podem precisar que a verificação de idade seja antecipada.
