// Base gerada pelo Supabase (generate_typescript_types) e enxugada: só o tipo Database, sem utilitários.
// Ajustes à mão: colunas preenchidas por gatilho são opcionais no Insert e argumentos de RPC aceitam null.
// Atualizar junto com cada migração.
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

type Lista = {
  Row: { ativo: boolean, id: number, nome: string }
  Insert: { ativo?: boolean, id?: never, nome: string }
  Update: { ativo?: boolean, id?: never, nome?: string }
  Relationships: []
}

type Rel<Nome extends string, Coluna extends string, Destino extends string> = {
  foreignKeyName: Nome
  columns: [Coluna]
  isOneToOne: false
  referencedRelation: Destino
  referencedColumns: ['id']
}

type Situacao = Database['public']['Enums']['situacao_manifestacao']
type Satisfacao = Database['public']['Enums']['nivel_satisfacao']

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: '14.18'
  }
  public: {
    Tables: {
      assuntos: Lista
      bairros: Lista
      diretorias: Lista
      identificacoes: Lista
      motivos_arquivamento: Lista
      tipos_manifestacao: Lista
      avaliadores: {
        Row: { ativo: boolean, diretoria_id: number, id: number, nome: string }
        Insert: { ativo?: boolean, diretoria_id: number, id?: never, nome: string }
        Update: { ativo?: boolean, diretoria_id?: number, id?: never, nome?: string }
        Relationships: [Rel<'avaliadores_diretoria_id_fkey', 'diretoria_id', 'diretorias'>]
      }
      canais: {
        Row: { ativo: boolean, exige_protocolo_falabr: boolean, id: number, nome: string, nome_painel: string }
        Insert: { ativo?: boolean, exige_protocolo_falabr?: boolean, id?: never, nome: string, nome_painel: string }
        Update: { ativo?: boolean, exige_protocolo_falabr?: boolean, id?: never, nome?: string, nome_painel?: string }
        Relationships: []
      }
      ciclos: {
        Row: {
          criado_em: string
          dia_zero: string
          id: number
          manifestacao_id: number
          numero: number
          prorrogacao_justificativa: string | null
          prorrogacao_registrada_em: string | null
          prorrogado: boolean
          respondido_em: string | null
          resposta: string | null
        }
        Insert: {
          criado_em?: string
          dia_zero: string
          id?: never
          manifestacao_id: number
          numero: number
          prorrogacao_justificativa?: string | null
          prorrogacao_registrada_em?: string | null
          prorrogado?: boolean
          respondido_em?: string | null
          resposta?: string | null
        }
        Update: {
          criado_em?: string
          dia_zero?: string
          id?: never
          manifestacao_id?: number
          numero?: number
          prorrogacao_justificativa?: string | null
          prorrogacao_registrada_em?: string | null
          prorrogado?: boolean
          respondido_em?: string | null
          resposta?: string | null
        }
        Relationships: [Rel<'ciclos_manifestacao_id_fkey', 'manifestacao_id', 'manifestacoes'>]
      }
      complementacoes: {
        Row: {
          arquivada_por_falta: boolean
          ciclo_id: number
          complementado_em: string | null
          criado_em: string
          id: number
          limite: string | null
          origem: Database['public']['Enums']['origem_complementacao']
          pedido_em: string
        }
        Insert: {
          arquivada_por_falta?: boolean
          ciclo_id: number
          complementado_em?: string | null
          criado_em?: string
          id?: never
          limite?: string | null
          origem: Database['public']['Enums']['origem_complementacao']
          pedido_em: string
        }
        Update: {
          arquivada_por_falta?: boolean
          ciclo_id?: number
          complementado_em?: string | null
          criado_em?: string
          id?: never
          limite?: string | null
          origem?: Database['public']['Enums']['origem_complementacao']
          pedido_em?: string
        }
        Relationships: [Rel<'complementacoes_ciclo_id_fkey', 'ciclo_id', 'ciclos'>]
      }
      encaminhamentos: {
        Row: {
          atual: boolean
          avaliador_id: number
          criado_em: string
          diretoria_id: number
          enviado_em: string
          id: number
          manifestacao_id: number
        }
        Insert: {
          atual?: boolean
          avaliador_id: number
          criado_em?: string
          diretoria_id: number
          enviado_em: string
          id?: never
          manifestacao_id: number
        }
        Update: {
          atual?: boolean
          avaliador_id?: number
          criado_em?: string
          diretoria_id?: number
          enviado_em?: string
          id?: never
          manifestacao_id?: number
        }
        Relationships: [
          Rel<'encaminhamentos_avaliador_id_fkey', 'avaliador_id', 'avaliadores'>,
          Rel<'encaminhamentos_diretoria_id_fkey', 'diretoria_id', 'diretorias'>,
          Rel<'encaminhamentos_manifestacao_id_fkey', 'manifestacao_id', 'manifestacoes'>,
        ]
      }
      feriados: {
        Row: { data: string, descricao: string, tipo: Database['public']['Enums']['tipo_feriado'] }
        Insert: { data: string, descricao: string, tipo: Database['public']['Enums']['tipo_feriado'] }
        Update: { data?: string, descricao?: string, tipo?: Database['public']['Enums']['tipo_feriado'] }
        Relationships: []
      }
      historico: {
        Row: {
          acao: string
          dados_antigos: Json | null
          dados_novos: Json | null
          em: string
          id: number
          registro_id: number
          tabela: string
          usuario_id: string | null
        }
        Insert: {
          acao: string
          dados_antigos?: Json | null
          dados_novos?: Json | null
          em?: string
          id?: never
          registro_id: number
          tabela: string
          usuario_id?: string | null
        }
        Update: {
          acao?: string
          dados_antigos?: Json | null
          dados_novos?: Json | null
          em?: string
          id?: never
          registro_id?: number
          tabela?: string
          usuario_id?: string | null
        }
        Relationships: []
      }
      manifestacoes: {
        Row: {
          ano: number
          arquivada: boolean
          assunto_id: number
          atualizado_em: string
          bairro_id: number | null
          cadastrado_em: string
          canal_id: number
          cep: string | null
          complemento: string | null
          criado_em: string
          criado_por: string | null
          descricao: string
          dia_zero: string
          dia_zero_corrigido_justificativa: string | null
          duplicada_de: number | null
          id: number
          identificacao_id: number
          logradouro: string | null
          motivo_arquivamento_id: number | null
          numero: string | null
          numero_imovel: string | null
          observacoes: string | null
          protocolo_falabr: string | null
          protocolo_mgouv: string | null
          resolutiva: boolean | null
          satisfacao_ouvidoria: Satisfacao | null
          satisfacao_resposta: Satisfacao | null
          sequencial: number
          situacao: Situacao
          tipo_id: number
        }
        // ano, sequencial e dia_zero são preenchidos pelo gatilho antes_inserir.
        Insert: {
          ano?: number
          arquivada?: boolean
          assunto_id: number
          atualizado_em?: string
          bairro_id?: number | null
          cadastrado_em: string
          canal_id: number
          cep?: string | null
          complemento?: string | null
          criado_em?: string
          criado_por?: string | null
          descricao: string
          dia_zero?: string
          dia_zero_corrigido_justificativa?: string | null
          duplicada_de?: number | null
          id?: never
          identificacao_id: number
          logradouro?: string | null
          motivo_arquivamento_id?: number | null
          numero_imovel?: string | null
          observacoes?: string | null
          protocolo_falabr?: string | null
          protocolo_mgouv?: string | null
          resolutiva?: boolean | null
          satisfacao_ouvidoria?: Satisfacao | null
          satisfacao_resposta?: Satisfacao | null
          sequencial?: number
          situacao?: Situacao
          tipo_id: number
        }
        Update: {
          arquivada?: boolean
          assunto_id?: number
          bairro_id?: number | null
          cadastrado_em?: string
          canal_id?: number
          cep?: string | null
          complemento?: string | null
          descricao?: string
          dia_zero?: string
          dia_zero_corrigido_justificativa?: string | null
          duplicada_de?: number | null
          id?: never
          identificacao_id?: number
          logradouro?: string | null
          motivo_arquivamento_id?: number | null
          numero_imovel?: string | null
          observacoes?: string | null
          protocolo_falabr?: string | null
          protocolo_mgouv?: string | null
          resolutiva?: boolean | null
          satisfacao_ouvidoria?: Satisfacao | null
          satisfacao_resposta?: Satisfacao | null
          situacao?: Situacao
          tipo_id?: number
        }
        Relationships: [
          Rel<'manifestacoes_assunto_id_fkey', 'assunto_id', 'assuntos'>,
          Rel<'manifestacoes_bairro_id_fkey', 'bairro_id', 'bairros'>,
          Rel<'manifestacoes_canal_id_fkey', 'canal_id', 'canais'>,
          Rel<'manifestacoes_duplicada_de_fkey', 'duplicada_de', 'manifestacoes'>,
          Rel<'manifestacoes_identificacao_id_fkey', 'identificacao_id', 'identificacoes'>,
          Rel<'manifestacoes_motivo_arquivamento_id_fkey', 'motivo_arquivamento_id', 'motivos_arquivamento'>,
          Rel<'manifestacoes_tipo_id_fkey', 'tipo_id', 'tipos_manifestacao'>,
        ]
      }
      pedidos_reabertura: {
        Row: {
          aceito: boolean | null
          ciclo_id: number | null
          criado_em: string
          decidido_em: string | null
          id: number
          justificativa_decisao: string | null
          manifestacao_id: number
          recebido_em: string
          texto: string
        }
        Insert: {
          aceito?: boolean | null
          ciclo_id?: number | null
          criado_em?: string
          decidido_em?: string | null
          id?: never
          justificativa_decisao?: string | null
          manifestacao_id: number
          recebido_em: string
          texto: string
        }
        Update: {
          aceito?: boolean | null
          ciclo_id?: number | null
          criado_em?: string
          decidido_em?: string | null
          id?: never
          justificativa_decisao?: string | null
          manifestacao_id?: number
          recebido_em?: string
          texto?: string
        }
        Relationships: [
          Rel<'pedidos_reabertura_ciclo_id_fkey', 'ciclo_id', 'ciclos'>,
          Rel<'pedidos_reabertura_manifestacao_id_fkey', 'manifestacao_id', 'manifestacoes'>,
        ]
      }
      usuarios: {
        Row: {
          ativo: boolean
          diretoria_id: number | null
          id: string
          nome: string
          perfil: Database['public']['Enums']['perfil_usuario']
        }
        Insert: {
          ativo?: boolean
          diretoria_id?: number | null
          id: string
          nome: string
          perfil: Database['public']['Enums']['perfil_usuario']
        }
        Update: {
          ativo?: boolean
          diretoria_id?: number | null
          id?: string
          nome?: string
          perfil?: Database['public']['Enums']['perfil_usuario']
        }
        Relationships: [Rel<'usuarios_diretoria_id_fkey', 'diretoria_id', 'diretorias'>]
      }
    }
    Views: {
      ciclos_prazos: {
        Row: {
          dia_zero: string | null
          id: number | null
          manifestacao_id: number | null
          no_prazo: boolean | null
          numero: number | null
          prazo: string | null
          prorrogado: boolean | null
          respondido_em: string | null
          tempo_dias_uteis: number | null
        }
        Relationships: [Rel<'ciclos_manifestacao_id_fkey', 'manifestacao_id', 'manifestacoes'>]
      }
      painel_manifestacoes: {
        Row: {
          ano: number | null
          arquivada: boolean | null
          assunto: string | null
          assunto_id: number | null
          avaliador: string | null
          bairro: string | null
          cadastrado_em: string | null
          canal: string | null
          canal_id: number | null
          ciclo: number | null
          dia_zero: string | null
          dias_restantes: number | null
          diretoria: string | null
          diretoria_id: number | null
          id: number | null
          logradouro: string | null
          no_prazo: boolean | null
          numero: string | null
          numero_imovel: string | null
          prazo: string | null
          protocolo_falabr: string | null
          protocolo_mgouv: string | null
          resolutiva: boolean | null
          respondido_em: string | null
          sequencial: number | null
          situacao: Situacao | null
          tipo: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      arquivar_manifestacao: {
        Args: { p_duplicada_de?: number | null, p_manifestacao_id: number, p_motivo_arquivamento_id: number }
        Returns: undefined
      }
      historico_manifestacao: {
        Args: { p_manifestacao_id: number }
        Returns: {
          acao: string
          dados_antigos: Json
          dados_novos: Json
          em: string
          id: number
          tabela: string
          usuario: string
        }[]
      }
      possiveis_duplicidades: {
        Args: {
          p_assunto_id: number | null
          p_ignorar_id?: number | null
          p_logradouro: string | null
          p_numero_imovel: string | null
          p_protocolo_falabr: string | null
          p_protocolo_mgouv: string | null
          p_referencia: string
        }
        Returns: { assunto: string, dia_zero: string, id: number, motivo: string, numero: string }[]
      }
      previa_prazos: {
        Args: { p_cadastrado_em: string }
        Returns: { dia_zero: string, prazo: string, prazo_prorrogado: string }[]
      }
      registrar_resposta: {
        Args: {
          p_arquivar?: boolean
          p_duplicada_de?: number | null
          p_manifestacao_id: number
          p_motivo_arquivamento_id?: number | null
          p_resolutiva?: boolean | null
          p_respondido_em: string
          p_resposta: string
        }
        Returns: undefined
      }
    }
    Enums: {
      nivel_satisfacao: 'muito_satisfeito' | 'satisfeito' | 'regular' | 'insatisfeito' | 'muito_insatisfeito'
      origem_complementacao: 'ouvidoria' | 'diretoria'
      perfil_usuario: 'administrador' | 'ouvidoria' | 'diretor'
      situacao_manifestacao: 'aguardando_complementacao' | 'em_tratamento' | 'prorrogada' | 'vencida' | 'respondida' | 'reaberta'
      tipo_feriado: 'nacional' | 'estadual' | 'municipal' | 'ponto_facultativo'
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}
